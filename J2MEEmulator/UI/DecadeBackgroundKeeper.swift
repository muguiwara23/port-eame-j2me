//
//  DecadeBackgroundKeeper.swift
//  J2MEEmulator
//
//  Decade Background Keepalive Engine for iOS.
//  Keeps J2ME threads and network sockets alive indefinitely in background / screen lock.
//  Uses continuous sub-audible audio stream with AVAudioSession .playback + .mixWithOthers,
//  chained background task assertions, and self-healing watchdog.
//

import UIKit
import AVFoundation

final class DecadeBackgroundKeeper: NSObject, AVAudioPlayerDelegate {
    static let shared = DecadeBackgroundKeeper()

    private var audioPlayer: AVAudioPlayer?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var watchdogTimer: DispatchSourceTimer?
    private(set) var isTreoActive: Bool = false

    private override init() {
        super.init()
        setupNotifications()
        // Restore persistent treo state if previously enabled
        let savedTreo = UserDefaults.standard.bool(forKey: "decade_treo_tat_man")
        if savedTreo {
            setTreoActive(true)
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    func setTreoActive(_ active: Bool) {
        isTreoActive = active
        UserDefaults.standard.set(active, forKey: "decade_treo_tat_man")

        if active {
            startKeepalive()
            UIApplication.shared.isIdleTimerDisabled = true
            startWatchdog()
            print("[DecadeBackgroundKeeper] Treo tắt màn & Chạy nền liên tục: ĐÃ BẬT")
        } else {
            stopWatchdog()
            stopKeepalive()
            UIApplication.shared.isIdleTimerDisabled = false
            print("[DecadeBackgroundKeeper] Treo tắt màn: ĐÃ TẮT")
        }
    }

    func startKeepalive() {
        startAudioStream()
        beginBackgroundTask()
    }

    func stopKeepalive() {
        audioPlayer?.stop()
        audioPlayer = nil
        endBackgroundTask()
    }

    @objc func onSceneDidEnterBackground() {
        if isTreoActive {
            startKeepalive()
        }
    }

    @objc private func handleAppDidEnterBackground() {
        if isTreoActive {
            startKeepalive()
        }
    }

    @objc private func handleAppWillEnterForeground() {
        endBackgroundTask()
        if isTreoActive && (audioPlayer == nil || audioPlayer?.isPlaying == false) {
            startAudioStream()
        }
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard isTreoActive,
              let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            // Re-activate and resume audio stream
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self, self.isTreoActive else { return }
                self.startAudioStream()
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard isTreoActive else { return }
        if audioPlayer == nil || audioPlayer?.isPlaying == false {
            startAudioStream()
        }
    }

    private func startAudioStream() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            if audioPlayer == nil {
                let pcmData = createSubaudibleWavData()
                audioPlayer = try AVAudioPlayer(data: pcmData)
                audioPlayer?.delegate = self
                audioPlayer?.numberOfLoops = -1 // Infinite continuous loop
                audioPlayer?.volume = 0.02      // Hardware level audio rendering active
                audioPlayer?.prepareToPlay()
            }
            if audioPlayer?.isPlaying == false {
                audioPlayer?.play()
            }
        } catch {
            print("[DecadeBackgroundKeeper] Audio setup error: \(error)")
        }
    }

    // AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if isTreoActive {
            player.play()
        }
    }

    private func beginBackgroundTask() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }

        bgTask = UIApplication.shared.beginBackgroundTask(withName: "DecadeKeepaliveTask") { [weak self] in
            // Expiration handler: renew immediately if treo is still active
            guard let self = self else { return }
            if self.isTreoActive {
                self.beginBackgroundTask()
            } else {
                self.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }

    /// Watchdog timer running on background queue to ensure audio is never killed
    private func startWatchdog() {
        stopWatchdog()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 3.0, repeating: 3.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isTreoActive else { return }
            DispatchQueue.main.async {
                if self.audioPlayer == nil || self.audioPlayer?.isPlaying == false {
                    self.startAudioStream()
                }
            }
        }
        timer.resume()
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    /// Synthesizes a valid 2-second 44.1kHz mono 16-bit PCM WAV with sub-audible LSB dither (-96dB).
    /// This guarantees iOS CoreAudio (mediaserverd) detects an ACTIVE audio stream and NEVER
    /// considers it digital silence or suspends the audio hardware.
    private func createSubaudibleWavData() -> Data {
        let sampleRate: Int32 = 44100
        let channels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let numSamples: Int32 = sampleRate * 2 // 2 seconds
        let dataSize: Int32 = numSamples * Int32(channels) * Int32(bitsPerSample / 8)
        let totalSize: Int32 = 36 + dataSize

        var data = Data()
        data.reserveCapacity(Int(totalSize + 8))

        // "RIFF"
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        data.append(withUnsafeBytes(of: totalSize.littleEndian) { Data($0) })
        // "WAVE"
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45])

        // "fmt " chunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
        let fmtSize: Int32 = 16
        data.append(withUnsafeBytes(of: fmtSize.littleEndian) { Data($0) })
        let pcmFormat: Int16 = 1
        data.append(withUnsafeBytes(of: pcmFormat.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        let byteRate: Int32 = sampleRate * Int32(channels) * Int32(bitsPerSample / 8)
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        let blockAlign: Int16 = channels * (bitsPerSample / 8)
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })

        // "data" chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        data.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })

        // 2 seconds of sub-audible dither (alternating +/-1 on 16-bit PCM = -96dB)
        for i in 0..<numSamples {
            let sample: Int16 = (i % 2 == 0) ? 1 : -1
            data.append(withUnsafeBytes(of: sample.littleEndian) { Data($0) })
        }
        return data
    }
}

//
//  DecadeBackgroundKeeper.swift
//  J2MEEmulator
//
//  Engine chạy ngầm 24/7 cho J2ME iOS: Treo tắt màn hình & Ra ngoài màn hình chính vĩnh viễn.
//  Giữ kết nối mạng TCP socket và luồng game hoạt động liên tục không bị ngắt.
//

import UIKit
import AVFoundation

final class DecadeBackgroundKeeper: NSObject, AVAudioPlayerDelegate {
    static let shared = DecadeBackgroundKeeper()

    private var audioPlayer: AVAudioPlayer?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var watchdogTimer: DispatchSourceTimer?

    var isTreoActive: Bool {
        get {
            // Mặc định luôn là TRUE để treo game liên tục theo yêu cầu người dùng
            if UserDefaults.standard.object(forKey: "decade_treo_tat_man") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "decade_treo_tat_man")
        }
        set {
            setTreoActive(newValue)
        }
    }

    private override init() {
        super.init()
        setupNotifications()
        if isTreoActive {
            startKeepalive()
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
        startWatchdog()
    }

    func stopKeepalive() {
        audioPlayer?.stop()
        audioPlayer = nil
        endBackgroundTask()
    }

    @objc func onSceneDidEnterBackground() {
        if isTreoActive {
            startKeepalive()
            beginGraceBackgroundTask()
        }
    }

    @objc private func handleAppDidEnterBackground() {
        if isTreoActive {
            startKeepalive()
            beginGraceBackgroundTask()
        }
    }

    @objc private func handleAppWillEnterForeground() {
        endBackgroundTask()
        if isTreoActive {
            if audioPlayer == nil || audioPlayer?.isPlaying == false {
                startAudioStream()
            }
        }
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard isTreoActive,
              let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            // Re-activate and resume audio stream immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self, self.isTreoActive else { return }
                self.startAudioStream()
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard isTreoActive else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isTreoActive else { return }
            if self.audioPlayer == nil || self.audioPlayer?.isPlaying == false {
                self.startAudioStream()
            }
        }
    }

    private func startAudioStream() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            if audioPlayer == nil || audioPlayer?.isPlaying == false {
                var player: AVAudioPlayer?
                if let bundleURL = Bundle.main.url(forResource: "silent", withExtension: "wav") {
                    player = try? AVAudioPlayer(contentsOf: bundleURL)
                }

                if player == nil {
                    let tempWavPath = NSTemporaryDirectory() + "/j2me_keepalive_silent.wav"
                    let fileURL = URL(fileURLWithPath: tempWavPath)
                    if !FileManager.default.fileExists(atPath: tempWavPath) {
                        let data = createSubaudibleWavData()
                        try? data.write(to: fileURL)
                    }
                    player = try? AVAudioPlayer(contentsOf: fileURL)
                }

                if player == nil {
                    let data = createSubaudibleWavData()
                    player = try? AVAudioPlayer(data: data)
                }

                audioPlayer = player
                audioPlayer?.delegate = self
                audioPlayer?.numberOfLoops = -1 // Vòng lặp vô tận
                audioPlayer?.volume = 0.02      // Giữ hardware audio pipeline luôn hoạt động trên iOS
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                print("[DecadeBackgroundKeeper] Audio keepalive loop đang phát liên tục.")
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

    /// Transient background task for seamless transition into background.
    /// Safely terminates without recursive chaining!
    private func beginGraceBackgroundTask() {
        endBackgroundTask()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "J2MEKeepaliveGrace") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if bgTask != .invalid {
            let t = bgTask
            bgTask = .invalid
            UIApplication.shared.endBackgroundTask(t)
        }
    }

    /// Watchdog timer running on utility queue to ensure audio is never stopped by iOS.
    private func startWatchdog() {
        stopWatchdog()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 4.0, repeating: 4.0)
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

        for i in 0..<numSamples {
            let sample: Int16 = (i % 2 == 0) ? 1 : -1
            data.append(withUnsafeBytes(of: sample.littleEndian) { Data($0) })
        }
        return data
    }
}

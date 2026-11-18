//
//  DecadeBackgroundKeeper.swift
//  J2MEEmulator
//
//  Engine chạy ngầm 24/7 cho J2ME iOS: Treo tắt màn hình & Ra ngoài màn hình chính vĩnh viễn.
//  - Sử dụng sóng hạ âm 16 Hz (-57 dB) non-zero PCM (không nghe thấy bằng tai/loa điện thoại)
//    với volume = 1.0 để mediaserverd KHÔNG BAO GIỜ phát hiện im lặng và cắt quyền chạy nền.
//  - Kích hoạt ngay khi mở app ở Foreground (trước khi khoá màn hình).
//  - Ngắt render đồ hoạ CoreGraphics & OpenGL ES khi tắt màn hình (giảm CPU về < 5%,
//    0 MB/s cấp phát bitmap) để chống iOS RunningBoard CPU limit & Jetsam kill 100%.
//  - Giữ toàn bộ luồng JVM, auto-farm và kết nối mạng TCP socket hoạt động liên tục 24/7.
//

import UIKit
import AVFoundation

final class DecadeBackgroundKeeper: NSObject, AVAudioPlayerDelegate {
    static let shared = DecadeBackgroundKeeper()

    private var audioPlayer: AVAudioPlayer?
    private var watchdogTimer: DispatchSourceTimer?
    private var ramCleanTimer: DispatchSourceTimer?

    var isTreoActive: Bool {
        get {
            if UserDefaults.standard.object(forKey: "decade_treo_tat_man") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "decade_treo_tat_man")
        }
        set {
            setTreoActive(newValue)
        }
    }

    var isAutoCleanRamActive: Bool {
        get {
            if UserDefaults.standard.object(forKey: "decade_auto_clean_ram") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "decade_auto_clean_ram")
        }
        set {
            setAutoCleanRamActive(newValue)
        }
    }

    private override init() {
        super.init()
        setupNotifications()
        if isTreoActive {
            startKeepalive()
        }
        if isAutoCleanRamActive {
            startAutoRamCleaner()
        }
    }

    private func setupNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        nc.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        nc.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance()
        )
        nc.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    func setAutoCleanRamActive(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: "decade_auto_clean_ram")
        if active {
            startAutoRamCleaner()
        } else {
            stopAutoRamCleaner()
        }
    }

    @objc private func handleMemoryWarning() {
        performRamCleanup(completion: nil)
    }

    /// Thực thi dọn dẹp RAM thực sự: ép MiniJVM GC, dọn bộ đệm ảnh CoreGraphics,
    /// xoá URLCache và trả trang nhớ malloc về kernel iOS (chống Jetsam kill khi treo lâu).
    func performRamCleanup(completion: ((Double, Double) -> Void)? = nil) {
        let beforeMB = Double(jvm_bridge_get_used_ram_kb()) / 1024.0
        URLCache.shared.removeAllCachedResponses()
        GameViewController.purgeInactiveSlotFrames()

        DispatchQueue.global(qos: .utility).async {
            jvm_bridge_clean_ram()
            Thread.sleep(forTimeInterval: 0.35)
            jvm_bridge_clean_ram()
            let afterMB = Double(jvm_bridge_get_used_ram_kb()) / 1024.0
            print(String(format: "[RAM Cleaner] %.1f MB -> %.1f MB", beforeMB, afterMB))
            if let cb = completion {
                DispatchQueue.main.async {
                    cb(beforeMB, afterMB)
                }
            }
        }
    }

    private func startAutoRamCleaner() {
        guard ramCleanTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 90.0, repeating: 90.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isAutoCleanRamActive else { return }
            self.performRamCleanup(completion: nil)
        }
        timer.resume()
        ramCleanTimer = timer
    }

    private func stopAutoRamCleaner() {
        ramCleanTimer?.cancel()
        ramCleanTimer = nil
    }

    func setTreoActive(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: "decade_treo_tat_man")

        if active {
            startKeepalive()
            UIApplication.shared.isIdleTimerDisabled = true
            print("[DecadeBackgroundKeeper] Treo tắt màn & Chạy nền 24/7: ĐÃ BẬT")
        } else {
            stopWatchdog()
            stopKeepalive()
            UIApplication.shared.isIdleTimerDisabled = false
            print("[DecadeBackgroundKeeper] Treo tắt màn: ĐÃ TẮT")
        }
    }

    func startKeepalive() {
        startAudioStream(forceRecreate: false)
        startWatchdog()
    }

    func stopKeepalive() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    @objc func onSceneWillResignActive() {
        if isTreoActive {
            // Đảm bảo audio đang chạy TRƯỚC KHI iOS chuyển app sang background!
            startAudioStream(forceRecreate: false)
        }
    }

    @objc func onSceneDidEnterBackground() {
        if !DecadePiPManager.shared.isPiPActive {
            // Bật chế độ ngắt render đồ hoạ CoreGraphics/GL để CPU < 5% và 0 MB/s memory churn
            j2me_render_set_background(1)
        }
        if isTreoActive {
            startKeepalive()
        }
        if isAutoCleanRamActive {
            performRamCleanup(completion: nil)
        }
    }

    @objc func onSceneWillEnterForeground() {
        j2me_render_set_background(0)
        if isTreoActive {
            startKeepalive()
        }
    }

    @objc private func handleAppWillResignActive() {
        onSceneWillResignActive()
    }

    @objc private func handleAppDidEnterBackground() {
        onSceneDidEnterBackground()
    }

    @objc private func handleAppWillEnterForeground() {
        onSceneWillEnterForeground()
    }

    @objc private func handleAppDidBecomeActive() {
        j2me_render_set_background(0)
        if isTreoActive {
            startKeepalive()
        }
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard isTreoActive,
              let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self, self.isTreoActive else { return }
                self.startAudioStream(forceRecreate: false)
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard isTreoActive else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isTreoActive else { return }
            if self.audioPlayer == nil || self.audioPlayer?.isPlaying == false {
                self.startAudioStream(forceRecreate: false)
            }
        }
    }

    @objc private func handleMediaServicesReset() {
        guard isTreoActive else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isTreoActive else { return }
            self.startAudioStream(forceRecreate: true)
        }
    }

    private func startAudioStream(forceRecreate: Bool) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])

            if forceRecreate {
                audioPlayer?.stop()
                audioPlayer = nil
            }

            if audioPlayer == nil {
                var player: AVAudioPlayer?
                if let bundleURL = Bundle.main.url(forResource: "silent", withExtension: "wav") {
                    player = try? AVAudioPlayer(contentsOf: bundleURL)
                }

                if player == nil {
                    let tempWavPath = NSTemporaryDirectory() + "/j2me_keepalive_16hz.wav"
                    let fileURL = URL(fileURLWithPath: tempWavPath)
                    if !FileManager.default.fileExists(atPath: tempWavPath) {
                        let data = createSubaudible16HzWavData()
                        try? data.write(to: fileURL)
                    }
                    player = try? AVAudioPlayer(contentsOf: fileURL)
                }

                if player == nil {
                    let data = createSubaudible16HzWavData()
                    player = try? AVAudioPlayer(data: data)
                }

                audioPlayer = player
                audioPlayer?.delegate = self
                audioPlayer?.numberOfLoops = -1 // Vòng lặp vô tận
                audioPlayer?.volume = 1.0       // PCM đã là sóng hạ âm 16Hz (-57dB) nên để 1.0 để mediaserverd luôn giữ pipeline!
                audioPlayer?.prepareToPlay()
            }

            if audioPlayer?.isPlaying == false {
                let ok = audioPlayer?.play() ?? false
                print("[DecadeBackgroundKeeper] Audio keepalive play=\(ok)")
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

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if isTreoActive {
            startAudioStream(forceRecreate: true)
        }
    }

    /// Watchdog timer kiểm tra mỗi 3 giây đảm bảo audio keepalive không bao giờ bị dừng.
    private func startWatchdog() {
        guard watchdogTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 3.0, repeating: 3.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isTreoActive else { return }
            DispatchQueue.main.async {
                if self.audioPlayer == nil || self.audioPlayer?.isPlaying == false {
                    self.startAudioStream(forceRecreate: false)
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

    /// Synthesizes a valid 10-second 44.1kHz mono 16-bit PCM WAV with continuous 16Hz -57dB sine wave.
    /// Completely inaudible to human ears & phone speakers, yet non-zero RMS energy so iOS mediaserverd
    /// never detects digital silence and never revokes the background playback assertion.
    private func createSubaudible16HzWavData() -> Data {
        let sampleRate: Int32 = 44100
        let channels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let numSamples: Int32 = sampleRate * 10 // 10 seconds
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

        let twoPiF = 2.0 * Double.pi * 16.0 / Double(sampleRate)
        for i in 0..<numSamples {
            let sample = Int16((45.0 * sin(twoPiF * Double(i))).rounded())
            data.append(withUnsafeBytes(of: sample.littleEndian) { Data($0) })
        }
        return data
    }
}

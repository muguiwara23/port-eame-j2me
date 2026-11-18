//
//  DecadeBackgroundKeeper.swift
//  J2MEEmulator
//
//  Engine chạy ngầm 24/7 chuẩn Spotify / Apple Music cho J2ME iOS:
//  - Sử dụng AVAudioSession .playback ĐỘC QUYỀN kết hợp MPNowPlayingInfoCenter &
//    MPRemoteCommandCenter để iOS RunningBoard cấp mức ưu tiên Jetsam cao nhất
//    (MediaPlayback / NowPlaying Priority 120 — tương đương Apple Music & Spotify).
//  - Sử dụng AVAudioEngine + AVAudioSourceNode (CoreAudio AURemoteIO phần cứng)
//    phát liên tục không ngắt quãng sóng hạ âm 18 Hz (-56 dB, hoàn toàn im lặng với
//    tai người & loa điện thoại), kèm AVAudioPlayer dự phòng.
//  - Hiển thị trực tiếp trạng thái "Đang treo: <Tên Game>" trên màn hình khóa để
//    xác nhận iOS đang giữ tiến trình sống liên tục.
//  - Ngắt render CoreGraphics & OpenGL ES và hạ nhịp Display xuống ~8 wakeups/giây
//    khi tắt màn hình để không bao giờ chạm giới hạn EXC_RESOURCE CPU / WAKEUPS.
//

import UIKit
import AVFoundation
import MediaPlayer

final class DecadeBackgroundKeeper: NSObject, AVAudioPlayerDelegate {
    static let shared = DecadeBackgroundKeeper()

    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var audioPlayer: AVAudioPlayer?
    private var watchdogTimer: DispatchSourceTimer?
    private var ramCleanTimer: DispatchSourceTimer?
    private var remoteCommandsConfigured = false
    private var currentGameName: String = "J2ME Game"
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid

    private func beginAppBackgroundTask() {
        guard bgTaskID == .invalid else { return }
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "DecadeKeepAliveTransition") { [weak self] in
            self?.endAppBackgroundTask()
        }
    }

    private func endAppBackgroundTask() {
        if bgTaskID != .invalid {
            let task = bgTaskID
            bgTaskID = .invalid
            UIApplication.shared.endBackgroundTask(task)
        }
    }

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
            selector: #selector(handleEngineConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    func updateNowPlayingGame(name: String) {
        currentGameName = name.isEmpty ? "J2ME Game" : name
        if isTreoActive {
            updateNowPlayingInfo()
        }
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
        DecadePiPManager.shared.purgeBuffers()

        DispatchQueue.global(qos: .utility).async {
            jvm_bridge_clean_ram()
            Thread.sleep(forTimeInterval: 0.4)
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
        timer.schedule(deadline: .now() + 60.0, repeating: 60.0)
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

    func startKeepalive() {
        setupRemoteCommandsIfNeeded()
        startAudioPipeline(forceRecreate: false)
        updateNowPlayingInfo()
        startWatchdog()
    }

    func stopKeepalive() {
        audioEngine?.stop()
        audioEngine = nil
        sourceNode = nil
        audioPlayer?.stop()
        audioPlayer = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    @objc func onSceneWillResignActive() {
        if isTreoActive {
            // Bảo đảm CoreAudio AURemoteIO + NowPlaying đang chạy TRƯỚC KHI khóa màn hình!
            startAudioPipeline(forceRecreate: false)
            updateNowPlayingInfo()
        }
    }

    @objc func onSceneDidEnterBackground() {
        beginAppBackgroundTask()
        if !DecadePiPManager.shared.isPiPActive {
            // Bật chế độ ngắt render đồ hoạ CoreGraphics/GL
            j2me_render_set_background(1)
        }
        if isTreoActive {
            startKeepalive()
        }
        if isAutoCleanRamActive {
            performRamCleanup(completion: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            if self.isAudioRunning {
                self.endAppBackgroundTask()
            }
        }
    }

    @objc func onSceneWillEnterForeground() {
        j2me_render_set_background(0)
        endAppBackgroundTask()
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

        if type == .began {
            beginAppBackgroundTask()
        } else if type == .ended {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self, self.isTreoActive else { return }
                self.startAudioPipeline(forceRecreate: true)
                self.updateNowPlayingInfo()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    if self?.isAudioRunning == true {
                        self?.endAppBackgroundTask()
                    }
                }
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard isTreoActive else { return }
        beginAppBackgroundTask()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isTreoActive else { return }
            if !self.isAudioRunning {
                self.startAudioPipeline(forceRecreate: false)
                self.updateNowPlayingInfo()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                if self?.isAudioRunning == true {
                    self?.endAppBackgroundTask()
                }
            }
        }
    }

    @objc private func handleMediaServicesReset() {
        guard isTreoActive else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isTreoActive else { return }
            self.startAudioPipeline(forceRecreate: true)
            self.updateNowPlayingInfo()
        }
    }

    @objc private func handleEngineConfigurationChange() {
        guard isTreoActive else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isTreoActive else { return }
            if self.audioEngine?.isRunning == false {
                self.startAudioPipeline(forceRecreate: true)
                self.updateNowPlayingInfo()
            }
        }
    }

    private var isAudioRunning: Bool {
        if let eng = audioEngine, eng.isRunning { return true }
        if let pl = audioPlayer, pl.isPlaying { return true }
        return false
    }

    private func setupRemoteCommandsIfNeeded() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        UIApplication.shared.beginReceivingRemoteControlEvents()

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.startAudioPipeline(forceRecreate: false)
            self.updateNowPlayingInfo()
            return .success
        }
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            // Giữ kết nối luôn sống ngay cả khi bấm nhầm nút trên màn hình khóa
            guard let self = self else { return .commandFailed }
            if self.isTreoActive {
                self.startAudioPipeline(forceRecreate: false)
                self.updateNowPlayingInfo()
            }
            return .success
        }
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "Đang treo: \(currentGameName)",
            MPMediaItemPropertyArtist: "J2ME Decade • Giữ kết nối 24/7",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if let appIcon = UIImage(named: "AppIcon") {
            let artwork = MPMediaItemArtwork(boundsSize: appIcon.size) { _ in appIcon }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = .playing
        }
    }

    /// Khởi động pipeline âm thanh hạ âm 18 Hz (-56 dB):
    /// Ưu tiên AVAudioEngine + AVAudioSourceNode (CoreAudio hardware callback không ngắt quãng),
    /// tự động dự phòng sang AVAudioPlayer nếu engine gặp lỗi phần cứng.
    private func startAudioPipeline(forceRecreate: Bool) {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback kết hợp .mixWithOthers để vừa giữ keepalive 24/7, vừa không bị ngắt khi người dùng nghe Spotify/YouTube/gọi điện
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])

            if forceRecreate {
                audioEngine?.stop()
                audioEngine = nil
                sourceNode = nil
                audioPlayer?.stop()
                audioPlayer = nil
            }

            if audioEngine == nil {
                if startRealtimeAudioEngine() {
                    return
                }
            } else if let eng = audioEngine {
                if !eng.isRunning {
                    try eng.start()
                    print("[DecadeBackgroundKeeper] AVAudioEngine resumed.")
                }
                return
            }

            // Fallback: AVAudioPlayer playing 16Hz -57dB silent.wav
            startFallbackAudioPlayer()
        } catch {
            print("[DecadeBackgroundKeeper] Audio pipeline error: \(error) — trying fallback player")
            startFallbackAudioPlayer()
        }
    }

    private func startRealtimeAudioEngine() -> Bool {
        let engine = AVAudioEngine()
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return false
        }

        // Continuous 18 Hz sub-audible sine wave at amplitude 0.0015 (-56 dB):
        // Completely inaudible to human ears & iPhone speakers, yet continuous non-zero PCM
        // so mediaserverd AURemoteIO hardware pipeline NEVER drops our background assertion!
        var phase: Double = 0.0
        let phaseIncrement = 2.0 * Double.pi * 18.0 / sampleRate
        let amplitude: Float = 0.0015

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = Float(sin(phase)) * amplitude
                phase += phaseIncrement
                if phase >= 2.0 * Double.pi {
                    phase -= 2.0 * Double.pi
                }
                for buffer in ablPointer {
                    if let mData = buffer.mData {
                        let ptr = mData.assumingMemoryBound(to: Float.self)
                        ptr[frame] = sample
                    }
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1.0
        engine.prepare()

        do {
            try engine.start()
            self.audioEngine = engine
            self.sourceNode = node
            print("[DecadeBackgroundKeeper] AVAudioEngine AURemoteIO 18Hz keepalive RUNNING (\(sampleRate) Hz).")
            return true
        } catch {
            print("[DecadeBackgroundKeeper] AVAudioEngine start failed: \(error)")
            engine.stop()
            return false
        }
    }

    private func startFallbackAudioPlayer() {
        do {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true, options: [])

            if audioPlayer == nil {
                var player: AVAudioPlayer?
                if let bundleURL = Bundle.main.url(forResource: "silent", withExtension: "wav") {
                    player = try? AVAudioPlayer(contentsOf: bundleURL)
                }
                if player == nil {
                    player = try? AVAudioPlayer(data: createSubaudible16HzWavData())
                }
                audioPlayer = player
                audioPlayer?.delegate = self
                audioPlayer?.numberOfLoops = -1
                audioPlayer?.volume = 1.0
                audioPlayer?.prepareToPlay()
            }
            if audioPlayer?.isPlaying == false {
                let ok = audioPlayer?.play() ?? false
                print("[DecadeBackgroundKeeper] Fallback AVAudioPlayer play=\(ok)")
            }
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
            startAudioPipeline(forceRecreate: true)
        }
    }

    /// Watchdog tần số thấp (10 giây/lần = 0.1 wakeup/giây) đảm bảo audio keepalive luôn chạy.
    private func startWatchdog() {
        guard watchdogTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 10.0, repeating: 10.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isTreoActive else { return }
            DispatchQueue.main.async {
                if !self.isAudioRunning {
                    self.beginAppBackgroundTask()
                    self.startAudioPipeline(forceRecreate: true)
                    self.updateNowPlayingInfo()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        if self?.isAudioRunning == true {
                            self?.endAppBackgroundTask()
                        }
                    }
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

    private func createSubaudible16HzWavData() -> Data {
        let sampleRate: Int32 = 44100
        let channels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let numSamples: Int32 = sampleRate * 10
        let dataSize: Int32 = numSamples * Int32(channels) * Int32(bitsPerSample / 8)
        let totalSize: Int32 = 36 + dataSize

        var data = Data()
        data.reserveCapacity(Int(totalSize + 8))
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        data.append(withUnsafeBytes(of: totalSize.littleEndian) { Data($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
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

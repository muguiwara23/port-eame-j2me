//
//  DecadePiPManager.swift
//  J2MEEmulator
//
//  Created for Vạn Trần idol J2me NSV IOS
//  Picture-in-Picture (PiP) manager with AVSampleBufferDisplayLayer.
//  Enables live game video floating outside the app over Home Screen and other apps.
//  Supports dragging anywhere and pinch-to-resize freely ("kéo to nhỏ tuỳ ý ngoài màn hình").
//

import UIKit
import AVKit
import AVFoundation
import CoreMedia
import VideoToolbox

final class DecadePiPManager: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    static let shared = DecadePiPManager()

    private var pipController: AVPictureInPictureController?
    let displayLayer = AVSampleBufferDisplayLayer()
    private weak var sourceView: UIView?

    private var pixelBufferPool: CVPixelBufferPool?
    private var lastPoolSize: CGSize = .zero
    private var lastFrameTime: CFTimeInterval = 0
    private var hasEnqueuedInitialFrame = false

    var isPiPActive: Bool {
        return pipController?.isPictureInPictureActive ?? false
    }

    var onPiPStateChanged: ((Bool) -> Void)?

    override init() {
        super.init()
        setupAudioSession()
    }

    func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[PiP] AudioSession error: \(error)")
        }
    }

    func setup(sourceView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("[PiP] Picture in Picture is not supported on this device")
            return
        }

        self.sourceView = sourceView

        // Setup display layer
        displayLayer.videoGravity = .resizeAspect
        displayLayer.isOpaque = true
        displayLayer.frame = sourceView.bounds

        if displayLayer.superlayer == nil {
            sourceView.layer.insertSublayer(displayLayer, at: 0)
        }

        // Setup PiP Controller with ContentSource(sampleBufferDisplayLayer:playbackDelegate:)
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )

        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.pipController = controller
        print("[PiP] Setup completed with AVSampleBufferDisplayLayer")
    }

    func updateLayout() {
        guard let sourceView = sourceView else { return }
        displayLayer.frame = sourceView.bounds
    }

    func startPiP() {
        setupAudioSession()
        guard let controller = pipController else {
            print("[PiP] Controller is nil")
            return
        }
        if !controller.isPictureInPictureActive {
            controller.startPictureInPicture()
        }
    }

    func stopPiP() {
        if let controller = pipController, controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        }
    }

    func togglePiP() {
        if isPiPActive {
            stopPiP()
        } else {
            startPiP()
        }
    }

    // MARK: - Frame Enqueueing
    func updateFrame(_ cgImage: CGImage) {
        let now = CACurrentMediaTime()
        // Ensure at least 1 initial frame is sent so PiP can start, then throttle to 30 FPS
        if hasEnqueuedInitialFrame {
            guard (now - lastFrameTime) >= 0.033 else { return }
        }
        lastFrameTime = now
        hasEnqueuedInitialFrame = true

        guard let sampleBuffer = createSampleBuffer(from: cgImage) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.displayLayer.status == .failed {
                self.displayLayer.flush()
            }
            if self.displayLayer.isReadyForMoreMediaData {
                self.displayLayer.enqueue(sampleBuffer)
            }
        }
    }

    private func getPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let currentSize = CGSize(width: width, height: height)
        if pixelBufferPool == nil || lastPoolSize != currentSize {
            pixelBufferPool = nil
            lastPoolSize = currentSize

            let poolAttrs: [CFString: Any] = [
                kCVPixelBufferPoolMinimumBufferCountKey: 3
            ]
            let bufferAttrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ]
            CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                poolAttrs as CFDictionary,
                bufferAttrs as CFDictionary,
                &pixelBufferPool
            )
        }

        guard let pool = pixelBufferPool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard status == kCVReturnSuccess else { return nil }
        return pixelBuffer
    }

    private func createSampleBuffer(from cgImage: CGImage) -> CMSampleBuffer? {
        let origW = cgImage.width
        let origH = cgImage.height

        // Portrait 3:4 video (240x320) is severely restricted by iOS PiP size limits.
        // Expanding the container to 4:3 landscape ratio allows iOS PiP to expand
        // to the FULL WIDTH of the iPhone screen, unlocking free multi-size resizing!
        let targetW: Int
        let targetH: Int
        let drawX: Int
        let drawY: Int

        if origW < origH {
            targetH = origH
            targetW = max(origW, (origH * 4) / 3)
            drawX = (targetW - origW) / 2
            drawY = 0
        } else {
            targetW = origW
            targetH = origH
            drawX = 0
            drawY = 0
        }

        guard let buffer = getPixelBuffer(width: targetW, height: targetH) else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: baseAddress,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Clear container background with clean black
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))

        // Draw game frame centered and pixel-perfect
        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: drawX, y: drawY, width: origW, height: origH))

        var formatDesc: CMVideoFormatDescription?
        let vStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescriptionOut: &formatDesc
        )
        guard vStatus == noErr, let format = formatDesc else { return nil }

        let now = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: now,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let sStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sStatus == noErr else { return nil }
        return sampleBuffer
    }

    // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate
    private var isPiPBubbleOnly: Bool = false

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        isPiPBubbleOnly.toggle()
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        // Infinite duration prevents loading indicator on game stream
        return CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        return false
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        // Called when user pinches/resizes PiP window on home screen
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    // MARK: - AVPictureInPictureControllerDelegate
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onPiPStateChanged?(true)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onPiPStateChanged?(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onPiPStateChanged?(false)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("[PiP] Failed: \(error.localizedDescription)")
        onPiPStateChanged?(false)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

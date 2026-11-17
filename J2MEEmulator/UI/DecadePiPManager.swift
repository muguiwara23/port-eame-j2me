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
            sourceView.layer.addSublayer(displayLayer)
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

        if isBubbleMode {
            // Draw clean dark background
            context.setFillColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.0)
            context.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))

            let centerX = CGFloat(targetW) / 2.0
            let centerY = CGFloat(targetH) / 2.0
            let bubbleRadius: CGFloat = 85.0

            // Outer cyan glowing halo
            context.setStrokeColor(red: 0.13, green: 0.59, blue: 0.95, alpha: 0.35)
            context.setLineWidth(10)
            context.strokeEllipse(in: CGRect(
                x: centerX - bubbleRadius - 3,
                y: centerY - bubbleRadius - 3,
                width: (bubbleRadius + 3) * 2,
                height: (bubbleRadius + 3) * 2
            ))

            // Main cyan ring
            context.setStrokeColor(red: 0.13, green: 0.59, blue: 0.95, alpha: 1.0)
            context.setLineWidth(4)
            context.strokeEllipse(in: CGRect(
                x: centerX - bubbleRadius,
                y: centerY - bubbleRadius,
                width: bubbleRadius * 2,
                height: bubbleRadius * 2
            ))

            // Inner circle base
            context.setFillColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 1.0)
            context.fillEllipse(in: CGRect(
                x: centerX - bubbleRadius + 2,
                y: centerY - bubbleRadius + 2,
                width: (bubbleRadius - 2) * 2,
                height: (bubbleRadius - 2) * 2
            ))

            // Clip to circle and draw live game thumbnail inside
            context.saveGState()
            let clipRadius = bubbleRadius - 6
            context.addEllipse(in: CGRect(
                x: centerX - clipRadius,
                y: centerY - clipRadius,
                width: clipRadius * 2,
                height: clipRadius * 2
            ))
            context.clip()

            let thumbW = CGFloat(origW) * (clipRadius * 2 / CGFloat(origH))
            let thumbH = clipRadius * 2
            let thumbX = centerX - thumbW / 2
            let thumbY = centerY - thumbH / 2
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: thumbX, y: thumbY, width: thumbW, height: thumbH))
            context.restoreGState()

            // Draw hint text
            context.saveGState()
            context.translateBy(x: 0, y: CGFloat(targetH))
            context.scaleBy(x: 1.0, y: -1.0)
            UIGraphicsPushContext(context)

            let hintText = "● BONG BÓNG • CHẠM ▶ MỞ CỬA SỔ ●"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: UIColor(red: 0.20, green: 0.75, blue: 1.0, alpha: 1.0)
            ]
            let textSize = (hintText as NSString).size(withAttributes: attrs)
            let textRect = CGRect(
                x: (CGFloat(targetW) - textSize.width) / 2,
                y: CGFloat(targetH) - 24,
                width: textSize.width,
                height: textSize.height
            )
            (hintText as NSString).draw(in: textRect, withAttributes: attrs)

            UIGraphicsPopContext()
            context.restoreGState()
        } else {
            // Clear container background with clean black
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))

            // Draw game frame centered and pixel-perfect
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: drawX, y: drawY, width: origW, height: origH))
        }

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
    var isBubbleMode: Bool = false

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        isBubbleMode.toggle()
        print("[PiP] Toggled bubble mode via center button: \(isBubbleMode)")
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
        return isBubbleMode
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
        isBubbleMode.toggle()
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

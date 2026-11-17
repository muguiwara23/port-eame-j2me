//
//  DecadePiPManager.swift
//  J2MEEmulator
//
//  Created for Vạn Trần idol J2me NSV IOS
//  Picture-in-Picture manager allowing J2ME gameplay to float over other apps and SpringBoard outside the app.
//

import UIKit
import AVKit

@available(iOS 15.0, *)
final class J2MEPiPVideoCallViewController: AVPictureInPictureVideoCallViewController {
    let canvasImageView = UIImageView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        canvasImageView.translatesAutoresizingMaskIntoConstraints = false
        canvasImageView.contentMode = .scaleAspectFit
        canvasImageView.layer.magnificationFilter = .nearest
        canvasImageView.layer.minificationFilter = .nearest
        view.addSubview(canvasImageView)

        NSLayoutConstraint.activate([
            canvasImageView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            canvasImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    func updateImage(_ cgImage: CGImage) {
        canvasImageView.layer.contents = cgImage
    }
}

final class DecadePiPManager: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = DecadePiPManager()

    private var pipController: AVPictureInPictureController?
    private var pipVideoCallVC: AnyObject? // J2MEPiPVideoCallViewController on iOS 15+
    private weak var currentSourceView: UIView?

    var isPiPActive: Bool {
        return pipController?.isPictureInPictureActive ?? false
    }

    var onPiPStateChanged: ((Bool) -> Void)?

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[PiP] AudioSession setup error: \(error)")
        }
    }

    func setup(sourceView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("[PiP] Picture in Picture is not supported on this device")
            return
        }

        self.currentSourceView = sourceView

        if #available(iOS 15.0, *) {
            let callVC = J2MEPiPVideoCallViewController()
            callVC.preferredContentSize = CGSize(width: 320, height: 240)
            self.pipVideoCallVC = callVC

            let contentSource = AVPictureInPictureController.ContentSource(
                activeVideoCallSourceView: sourceView,
                contentViewController: callVC
            )

            let controller = AVPictureInPictureController(contentSource: contentSource)
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            self.pipController = controller
            print("[PiP] Setup completed successfully")
        }
    }

    func startPiP() {
        setupAudioSession()
        guard let controller = pipController else {
            print("[PiP] pipController is nil")
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

    func updateFrame(_ cgImage: CGImage) {
        if #available(iOS 15.0, *) {
            if let vc = pipVideoCallVC as? J2MEPiPVideoCallViewController {
                DispatchQueue.main.async {
                    vc.updateImage(cgImage)
                }
            }
        }
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
}

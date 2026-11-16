//
//  DecadeFloatingBubble.swift
//  J2MEEmulator
//
//  Stub implementation (Floating Bubble removed per user request)
//

import UIKit

final class DecadeFloatingBubble: UIView {
    static let shared = DecadeFloatingBubble()

    var onRestoreGame: (() -> Void)?
    var onAssignProxy: (() -> Void)?
    var onToggleTreo: (() -> Void)?
    var onToggleHeadless: (() -> Void)?
    var onSelectTabPrompt: (() -> Void)?
    var onTogglePiP: (() -> Void)?

    func setGameInfo(name: String, icon: UIImage?, tabNumber: Int) {}
    func show(in window: UIWindow?) {}
    func dismissAssistiveTouchMenu(animated: Bool) {}
}

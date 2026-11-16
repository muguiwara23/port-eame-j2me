//
//  DecadePiPManager.swift
//  J2MEEmulator
//
//  Stub implementation (PiP removed per user request)
//

import UIKit

final class DecadePiPManager: NSObject {
    static let shared = DecadePiPManager()
    var isPiPActive: Bool { false }

    override init() {
        super.init()
    }

    func attachDisplayLayer(to view: UIView) {}
    func togglePiP() {}
}

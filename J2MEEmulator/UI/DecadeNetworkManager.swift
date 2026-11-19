//
//  DecadeNetworkManager.swift
//  J2MEEmulator
//
//  Decade Smart Network Handover Engine.
//  Monitors active network interfaces (Wi-Fi <-> 5G/4G/LTE) and enables seamless
//  transitioning so game connections remain uninterrupted when switching networks.
//

import Foundation
import Network
import UIKit

final class DecadeNetworkManager {
    static let shared = DecadeNetworkManager()

    enum InterfaceType {
        case wifi
        case cellular
        case other
        case none

        var displayName: String {
            switch self {
            case .wifi: return "Wi-Fi"
            case .cellular: return "Datos móviles"
            case .other: return "Cable u otra"
            case .none: return "Sin conexión"
            }
        }

        var icon: String {
            switch self {
            case .wifi: return "wifi"
            case .cellular: return "antenna.radiowaves.left.and.right"
            case .other: return "network"
            case .none: return "wifi.slash"
            }
        }
    }

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.decade.network.monitor", qos: .utility)

    private(set) var currentType: InterfaceType = .none
    private(set) var isConnected: Bool = false
    private var hasInitialPath = false

    var onNetworkSwitched: ((InterfaceType, String) -> Void)?

    private init() {
        startMonitoring()
    }

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
        monitor.start(queue: monitorQueue)
    }

    private func handlePathUpdate(_ path: NWPath) {
        let connected = (path.status == .satisfied)
        var newType: InterfaceType = .none

        if connected {
            if path.usesInterfaceType(.wifi) {
                newType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                newType = .cellular
            } else {
                newType = .other
            }
        }

        let oldType = self.currentType
        self.isConnected = connected
        self.currentType = newType

        if !hasInitialPath {
            hasInitialPath = true
            print("[DecadeNetworkManager] Initial network: \(newType.displayName) (Connected: \(connected))")
            return
        }

        // Detect seamless transition (Wi-Fi -> Cellular or Cellular -> Wi-Fi)
        if oldType != newType && connected {
            let msg: String
            if oldType == .wifi && newType == .cellular {
                msg = "📶 Ahora por datos móviles"
                print("[DecadeNetworkManager] Seamless failover: Wi-Fi lost -> 5G/Cellular active")
            } else if oldType == .cellular && newType == .wifi {
                msg = "📶 Ahora por Wi-Fi"
                print("[DecadeNetworkManager] Seamless failover: Cellular -> Wi-Fi active")
            } else {
                msg = "📶 Red: \(newType.displayName)"
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onNetworkSwitched?(newType, msg)
                NotificationCenter.default.post(
                    name: NSNotification.Name("DecadeNetworkSwitched"),
                    object: nil,
                    userInfo: ["type": newType, "message": msg]
                )
            }
        } else if !connected && oldType != .none {
            let msg = "⚠️ Sin conexión. Buscando red..."
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onNetworkSwitched?(.none, msg)
                NotificationCenter.default.post(
                    name: NSNotification.Name("DecadeNetworkSwitched"),
                    object: nil,
                    userInfo: ["type": InterfaceType.none, "message": msg]
                )
            }
        }
    }

    func currentNetworkDescription() -> String {
        return isConnected ? currentType.displayName : "Sin conexión"
    }
}

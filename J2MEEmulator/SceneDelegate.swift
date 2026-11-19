//
//  SceneDelegate.swift
//  J2MEEmulator
//
//  Created by Alexander Goremykin on 19.03.2026.
//

import UIKit

/// Forwards orientation queries to the top view controller
private class OrientationNavigationController: UINavigationController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        topViewController?.supportedInterfaceOrientations ?? .portrait
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // Port/eame: its own launcher (PortEame/PELauncherViewController.swift).
        let vc = PELauncherViewController()
        let nav = OrientationNavigationController(rootViewController: vc)
        nav.navigationBar.prefersLargeTitles = false

        // Clean light navigation bar (matching Android Decade light theme)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        let titleColor = UIColor(red: 0.12, green: 0.16, blue: 0.22, alpha: 1.0)
        appearance.titleTextAttributes = [.foregroundColor: titleColor, .font: UIFont.systemFont(ofSize: 18, weight: .bold)]
        appearance.largeTitleTextAttributes = [.foregroundColor: titleColor]

        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance
        nav.navigationBar.tintColor = titleColor

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = nav
        window?.makeKeyAndVisible()

        // Port/eame: opened by a shortcut (porteame-java://) or with a .jar.
        if let url = connectionOptions.urlContexts.first?.url {
            PELauncherViewController.open(url)
        }
    }

    // Port/eame: a shortcut (porteame-java://jugar?juego=...) or "Open in"
    // with a .jar while the app runs.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            PELauncherViewController.open(context.url)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        DecadeBackgroundKeeper.shared.clearLockScreenNotification()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        DecadeBackgroundKeeper.shared.clearLockScreenNotification()
        DecadeBackgroundKeeper.shared.onSceneWillEnterForeground()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        DecadeBackgroundKeeper.shared.onSceneWillResignActive()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        DecadeBackgroundKeeper.shared.clearLockScreenNotification()
        DecadeBackgroundKeeper.shared.onSceneWillEnterForeground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        DecadeBackgroundKeeper.shared.onSceneDidEnterBackground()
    }
}

//
//  SceneDelegate.swift
//  TobyTunes
//
//  Owns the app's window and handles foreground/background transitions
//  (UIScene lifecycle). The UI is loaded from Main.storyboard, as configured
//  in Info.plist under UIApplicationSceneManifest.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private var appDelegate: AppDelegate? {
        return UIApplication.shared.delegate as? AppDelegate
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // The storyboard (UISceneStoryboardFile) creates the window and root view controller automatically.
        guard scene is UIWindowScene else { return }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Was applicationDidBecomeActive
        appDelegate?.isUIActive = true
        Bookmarks.updateBookmarks()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Was applicationDidEnterBackground
        appDelegate?.isUIActive = false
    }
}

//
//  TTTabBarController.swift
//  TobyTunes
//
//  Created by Toby Nelson on 28/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import Foundation
import UIKit
import MediaPlayer

let nowPlayingTabIndex = 2

class TTTabBarController: UITabBarController {
    /// SF Symbols for each tab, keyed by the tab's title in the storyboard: (normal, selected).
    private let tabSymbols: [String: (String, String)] = [
        "Genres":      ("square.stack",  "square.stack.fill"),
        "Artists":     ("music.mic",     "music.mic"),
        "Now Playing": ("play.circle",   "play.circle.fill"),
        "Bookmarks":   ("bookmark",      "bookmark.fill"),
        "About":       ("info.circle",   "info.circle.fill"),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()

        for controller in viewControllers ?? [] {
            if let title = controller.tabBarItem.title, let symbols = tabSymbols[title] {
                controller.tabBarItem.image = UIImage(systemName: symbols.0)
                controller.tabBarItem.selectedImage = UIImage(systemName: symbols.1)
            }
            // Large titles on the list screens (Now Playing opts out itself)
            (controller as? UINavigationController)?.navigationBar.prefersLargeTitles = true
        }

        // Solid tab bar background (white in Light Mode, black in Dark Mode) instead of
        // see-through glass, so it looks the same over every screen, including Now Playing.
        // Both appearances are set: iOS falls back to glass for whichever one is left unset.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.isTranslucent = false

        // Keep the tab bar's light/dark style fixed to the phone's setting on every tab,
        // including the dark Now Playing screen
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: TTTabBarController, _: UITraitCollection) in
            controller.pinTabBarStyle()
        }
        pinTabBarStyle()

        // If music is currently playing
        if Player.sharedInstance.playState() == .Playing {
            // Go to now playing tab
            self.selectedIndex = nowPlayingTabIndex
        }
    }

    /// Fixes the tab bar to the phone's light/dark setting, so it looks the same on every tab.
    /// Left to itself, iOS 26's glass tab bar turns dark over dark content such as Now Playing,
    /// and that switch visibly lags behind the screen change.
    func pinTabBarStyle() {
        let style: UIUserInterfaceStyle = traitCollection.userInterfaceStyle == .dark ? .dark : .light
        UIView.performWithoutAnimation {
            tabBar.overrideUserInterfaceStyle = style
            tabBar.layoutIfNeeded()
        }
    }
}
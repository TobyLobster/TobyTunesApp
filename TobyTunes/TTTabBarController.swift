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

    /// Neutral colour of the area around the tab bar (the strip above it and the space around its
    /// capsule): soft grey in Light Mode, near-black grey in Dark Mode.
    static let tabBarSurroundColour = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x16/255.0, green: 0x16/255.0, blue: 0x18/255.0, alpha: 1)
            : UIColor(red: 0xEE/255.0, green: 0xE5/255.0, blue: 0xEA/255.0, alpha: 1)
    }

    /// The tab bar itself: white in Light Mode, dark grey in Dark Mode, so it stands out from its surround.
    static let tabBarColour = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x2C/255.0, green: 0x2C/255.0, blue: 0x2E/255.0, alpha: 1)
            : UIColor.white
    }

    /// Space between each screen's content and the tab bar.
    static let tabBarMargin: CGFloat = 12

    /// Strip in the tab bar's own colour just above it, so content never runs right up to the tab bar.
    private let tabBarMarginView = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()

        tabBarMarginView.backgroundColor = TTTabBarController.tabBarSurroundColour
        view.backgroundColor = TTTabBarController.tabBarSurroundColour
        tabBarMarginView.isUserInteractionEnabled = false
        view.insertSubview(tabBarMarginView, belowSubview: tabBar)
        // Every screen's safe area stops above the strip: lists leave room below their last row,
        // and Now Playing's controls sit above it
        for controller in viewControllers ?? [] {
            controller.additionalSafeAreaInsets.bottom = TTTabBarController.tabBarMargin
        }

        for controller in viewControllers ?? [] {
            if let title = controller.tabBarItem.title, let symbols = tabSymbols[title] {
                controller.tabBarItem.image = UIImage(systemName: symbols.0)
                controller.tabBarItem.selectedImage = UIImage(systemName: symbols.1)
            }
            // Large titles on the list screens (Now Playing opts out itself)
            (controller as? UINavigationController)?.navigationBar.prefersLargeTitles = true
        }

        // Solid tab bar background (white in Light Mode, dark grey in Dark Mode) instead of
        // see-through glass, so it looks the same over every screen, including Now Playing.
        // Both appearances are set: iOS falls back to glass for whichever one is left unset.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = TTTabBarController.tabBarColour
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.isTranslucent = false
        refreshTabBarLayout()

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

    /// iOS 26 can measure the tab titles before the tab bar has finished laying out when it has
    /// a custom appearance, leaving them cut short ("Now Play…", "Bookmar…"). Re-applying the
    /// appearance and laying out straight away makes it measure them again at the right size.
    func refreshTabBarLayout() {
        let standard = tabBar.standardAppearance
        tabBar.standardAppearance = standard
        tabBar.scrollEdgeAppearance = tabBar.scrollEdgeAppearance ?? standard
        tabBar.setNeedsLayout()
        tabBar.layoutIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let margin = TTTabBarController.tabBarMargin
        tabBarMarginView.frame = CGRect(x: 0, y: tabBar.frame.minY - margin, width: view.bounds.width, height: margin)
        // Keep it above the screens (they're swapped in and out as tabs change) but below the tab bar
        view.insertSubview(tabBarMarginView, belowSubview: tabBar)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // First chance to measure the titles at the tab bar's real on-screen size
        refreshTabBarLayout()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // The titles change between side by side (landscape) and stacked (portrait): re-measure after rotating
        coordinator.animate(alongsideTransition: nil) { _ in
            self.refreshTabBarLayout()
        }
    }

    /// Fixes the tab bar to the phone's light/dark setting, so it looks the same on every tab.
    /// Left to itself, iOS 26's glass tab bar turns dark over dark content such as Now Playing,
    /// and that switch visibly lags behind the screen change.
    func pinTabBarStyle() {
        let style: UIUserInterfaceStyle = traitCollection.userInterfaceStyle == .dark ? .dark : .light
        UIView.performWithoutAnimation {
            tabBar.overrideUserInterfaceStyle = style
            tabBarMarginView.overrideUserInterfaceStyle = style
            tabBar.layoutIfNeeded()
        }
    }
}

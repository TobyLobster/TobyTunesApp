//
//  TTSegue.swift
//  TobyTunes
//
//  Created by Toby Nelson on 09/07/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import Foundation
import UIKit

class TTSegue : UIStoryboardSegue {
    override init(identifier: String?, source: UIViewController, destination: UIViewController) {
        if let mydest = source.tabBarController?.viewControllers![nowPlayingTabIndex] {
            super.init(identifier: identifier, source:source, destination: mydest)
        }
        else {
            super.init(identifier: identifier, source:source, destination: destination)
        }
    }

    override func perform() {
        let source = self.source
        let fromTabIndex = source.tabBarController?.selectedIndex
        let destination = self.destination
        source.tabBarController?.selectedViewController = destination

        if let nowPlayingNavController = destination as? NowPlayingNavigationController {
            if let nowPlayingViewController = nowPlayingNavController.viewControllers.first as? NowPlayingViewController {
                if fromTabIndex != nil {
                    nowPlayingViewController.fromTabIndex = fromTabIndex!
                }
                else {
                    nowPlayingViewController.fromTabIndex = 0
                }
            }
        }

        source.tabBarController?.selectedIndex = nowPlayingTabIndex
    }
}

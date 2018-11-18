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
    override func viewDidLoad() {
        // If music is currently playing
        if Player.sharedInstance.playState() == .Playing {
            // Go to now playing tab
            self.selectedIndex = nowPlayingTabIndex
        }
    }
}
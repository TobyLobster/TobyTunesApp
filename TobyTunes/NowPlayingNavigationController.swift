//
//  NowPlayingNavigationController.swift
//  TobyTunes
//
//  Created by Toby Nelson on 10/07/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import Foundation
import UIKit

class NowPlayingNavigationController : UINavigationController, UINavigationBarDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        // Now Playing always sits on a dark, artwork-coloured background, whatever the system setting
        overrideUserInterfaceStyle = .dark
        navigationBar.tintColor = .white
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    func navigationController(navigationController: UINavigationController, willShowViewController viewController: UIViewController, animated: Bool) {
        //print("hello")
    }
}
//
//  AboutViewController.swift
//  TobyTunes
//
//  Created by Toby Nelson on 14/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import UIKit

class AboutViewController: UIViewController {
    @IBOutlet weak var versionLabel: UILabel?
    @IBOutlet weak var agcSlider: UISlider?
    var dragging = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view, typically from a nib.
        let appVersionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if appVersionString != nil {
            var versionString: String = "Version \(appVersionString!)"
            if buildNumber != nil {
                versionString = versionString + ", Build \(buildNumber!)"
            }
            versionLabel?.text = versionString
        }

        // Load user setting
        agcSlider?.value = audioEffectAmount
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func dragStart(sender: UISlider) {
        dragging = true
    }

    @IBAction func draggingInside(sender: UISlider) {
        if agcSlider != nil {
            audioEffectAmount = agcSlider!.value
        }
    }

    @IBAction func draggingOutside(sender: UISlider) {
        if agcSlider != nil {
            audioEffectAmount = agcSlider!.value
        }
    }

    @IBAction func dragStop(sender: UISlider) {
        dragging = false
        if agcSlider != nil {
            audioEffectAmount = agcSlider!.value
        }
    }

    @IBAction func slide(sender: UISlider) {
        dragging = false
        if agcSlider != nil {
            audioEffectAmount = agcSlider!.value
            UserDefaults.standard.set(audioEffectAmount, forKey: "agc")
        }
    }
    

}

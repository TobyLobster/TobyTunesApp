//
//  AppDelegate.swift
//  TobyTunes
//
//  Created by Toby Nelson on 14/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import UIKit
import MediaPlayer

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var isUIActive = true

    private func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: Any]?) -> Bool {

        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback, mode: AVAudioSession.Mode.default)
        } catch let error as NSError {
            print(error.description)
        }
        audioEffectAmount = UserDefaults.standard.float(forKey: "agc")

        // Override points for customization
        //MPRemoteCommandCenter.sharedCommandCenter().changePlaybackRateCommand
        //MPRemoteCommandCenter.sharedCommandCenter().disableLanguageOptionCommand
        //MPRemoteCommandCenter.sharedCommandCenter().dislikeCommand
        //MPRemoteCommandCenter.sharedCommandCenter().enableLanguageOptionCommand
        //MPRemoteCommandCenter.sharedCommandCenter().likeCommand
        //MPRemoteCommandCenter.sharedCommandCenter().ratingCommand
        //MPRemoteCommandCenter.sharedCommandCenter().bookmarkCommand
        //MPRemoteCommandCenter.sharedCommandCenter().changePlaybackPositionCommand
        MPRemoteCommandCenter.shared().pauseCommand.addTarget(handler: { (event) -> MPRemoteCommandHandlerStatus in
            Player.sharedInstance.pause()
            return .success
        })
        MPRemoteCommandCenter.shared().playCommand.addTarget(handler: { (event) -> MPRemoteCommandHandlerStatus in
            if Player.sharedInstance.play() {
                return .success
            }
            return .commandFailed
        })

        MPRemoteCommandCenter.shared().nextTrackCommand.addTarget(handler: { (event) -> MPRemoteCommandHandlerStatus in
            Player.sharedInstance.skipToNextItem()
            return .success
        })

        MPRemoteCommandCenter.shared().previousTrackCommand.addTarget(handler: { (event) -> MPRemoteCommandHandlerStatus in
            Player.sharedInstance.skipToPreviousItem()
            return .success
        })

        MPRemoteCommandCenter.shared().seekBackwardCommand.addTarget(handler: { (event) -> MPRemoteCommandHandlerStatus in
            Player.sharedInstance.beginFastBackwardPlay()
            return .success
        })
        MPRemoteCommandCenter.shared().seekForwardCommand.addTarget(handler: { (event) -> MPRemoteCommandHandlerStatus in
            Player.sharedInstance.beginFastForwardPlay()
            return .success
        })
        MPRemoteCommandCenter.shared().skipBackwardCommand.addTarget(handler: { (event) -> MPRemoteCommandHandlerStatus in
            if let skipIntervalEvent = event as? MPSkipIntervalCommandEvent {
                Player.sharedInstance.skipBackwards(skipTime: skipIntervalEvent.interval)
            }
            else {
                Player.sharedInstance.skipBackwards()
            }
            return .success
        })
        MPRemoteCommandCenter.shared().skipBackwardCommand.preferredIntervals = [30]
        MPRemoteCommandCenter.shared().skipForwardCommand.addTarget(handler: { (event) -> MPRemoteCommandHandlerStatus in
            if let skipIntervalEvent = event as? MPSkipIntervalCommandEvent {
                Player.sharedInstance.skipForwards(skipTime: skipIntervalEvent.interval)
            }
            else {
                Player.sharedInstance.skipForwards()
            }
            return .success
        })
        MPRemoteCommandCenter.shared().skipForwardCommand.preferredIntervals = [30]
        MPRemoteCommandCenter.shared().stopCommand.addTarget(handler: { (event) -> MPRemoteCommandHandlerStatus in
            Player.sharedInstance.stop()
            return .success
        })
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.addTarget(handler: { (event) -> MPRemoteCommandHandlerStatus in
            Player.sharedInstance.togglePlayPause()
            return .success
        })
        Bookmarks.load()
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        isUIActive = false
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        isUIActive = true
        Bookmarks.updateBookmarks()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVAudioSessionCategory(_ input: AVAudioSession.Category) -> String {
	return input.rawValue
}

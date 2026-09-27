//
//  AppDelegate.swift
//  TobyTunes
//
//  Created by Toby Nelson on 14/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import UIKit
import MediaPlayer

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // Set by SceneDelegate as the app moves between foreground and background
    var isUIActive = true

    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        do {
            // The playback category supports AirPlay and Bluetooth (A2DP) automatically.
            // The allowAirPlay / allowBluetooth* options are only valid with playAndRecord,
            // and passing them here makes setCategory fail with error -50.
            try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback,
                                                            mode: AVAudioSession.Mode.default,
                                                            options: [])
            try AVAudioSession.sharedInstance().setActive(true)
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
        Bookmarks.removeOrphanedPlaylistBookmarks()
        return true
    }

    // MARK: UISceneSession Lifecycle
    // Foreground/background handling now lives in SceneDelegate.

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

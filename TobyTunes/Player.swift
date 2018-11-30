//
//  Player.swift
//  TobyTunes
//
//  Created by Toby Nelson on 05/08/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer

struct PlayerTrack {
    var persistentID: UInt64
}

struct PlayerQueue {
    var tracks: [PlayerTrack] = []

    func findTrackIndex(persistentID: UInt64) -> Int? {
        for (index, track) in tracks.enumerated() {
            if track.persistentID == persistentID {
                return index
            }
        }
        return nil
    }

    func findTrack(persistentID: UInt64) -> PlayerTrack? {
        for track in tracks {
            if track.persistentID == persistentID {
                return track
            }
        }
        return nil
    }
}

enum PlaybackState {
    case Initialising, Stopped, Playing, Paused, Failed
}

enum PlaybackSeekingState {
    case NotSeeking, Seeking
}

enum PlaybackReadinessState {
    case Initialising, Ready, Failed
}

enum PlaybackRequestedState {
    case Nothing, PlayRequested, PauseRequested
}

class PlayingTrack {
    static var statusContext = "StatusContext"
    static var rateContext = "RateContext"

    var avPlayer: AVPlayer
    var playerItem: AVPlayerItem
    var persistentID: UInt64
    var playbackReadinessState: PlaybackReadinessState
    var playbackRequestedState: PlaybackRequestedState
    var seekingState: PlaybackSeekingState
    weak var observer: Player?
    var timeObserver: Any?
    var requestedSeekTime: Double?
    var seekStartTime: NSDate

    let tapInit: MTAudioProcessingTapInitCallback = {
        (tap, clientInfo, tapStorageOut) in
        //print("init \(tap, clientInfo, tapStorageOut)\n")
        //			tapStorageOut.assignFrom(source:clientInfo, count: 1)
        //			tapStorageOut.init(clientInfo)
    }

    let tapFinalize: MTAudioProcessingTapFinalizeCallback = {
        (tap) in
        //print("finalize \(tap)\n")
    }

    let tapPrepare: MTAudioProcessingTapPrepareCallback = {
        (tap, b, c) in
        //print("prepare: \(tap, b, c)\n")
    }

    let tapUnprepare: MTAudioProcessingTapUnprepareCallback = {
        (tap) in
        //print("unprepare \(tap)\n")
    }

    let tapProcess: MTAudioProcessingTapProcessCallback = {
        (tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut) in
        tap_ProcessCallback(tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut)
        /*
        //print("callback \(tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut)\n")

        let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
        if status == 0 {
            let bufferList = bufferListInOut.memory /* as AudioBufferList */
            for bufferIndex in 0..<bufferList.mNumberBuffers {
                let buffer = bufferList.mBuffers.
                let samples = numberFrames * (isNonInterleaved ? 1 : buffer.)
            }
        }
         */
    }

    func createAudioFilterForPlayerItem() {
        // Create audio filter
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess)

        var tap: Unmanaged<MTAudioProcessingTap>?
        let err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)

        if err != 0 {
            print("err: \(err)")
        }

        //print("tracks? \(playerItem.asset.tracks)\n")

        let audioTrack = playerItem.asset.tracks(withMediaType: AVMediaType.audio).first!
        let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
        inputParams.audioTapProcessor = tap?.takeUnretainedValue()

        // print("inputParms: \(inputParams), \(inputParams.audioTapProcessor)\n")
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParams]

        playerItem.audioMix = audioMix
    }

    init(URL: URL, persistentID: UInt64, observer: Player) {
        self.playerItem             = AVPlayerItem(url: URL)
        self.avPlayer               = AVPlayer(playerItem: playerItem)
        self.playbackReadinessState = .Initialising
        self.playbackRequestedState = .Nothing
        self.seekingState           = .NotSeeking
        self.observer               = observer
        self.persistentID           = persistentID
        self.requestedSeekTime      = nil
        self.seekStartTime          = NSDate(timeIntervalSince1970: 0)

        self.playerItem.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithm.timeDomain
        createAudioFilterForPlayerItem()

        // Add observers
        self.avPlayer.addObserver(observer,   forKeyPath: "status", options: NSKeyValueObservingOptions(), context: &PlayingTrack.statusContext)
        self.avPlayer.addObserver(observer,   forKeyPath: "rate",   options: .new,                         context: &PlayingTrack.rateContext)

        // Add notification
        NotificationCenter.default.addObserver(observer,
                                               selector: #selector(Player.playbackFinished),
                                               name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                               object: self.playerItem)

        // Add update time code block - called every 0.5 seconds
        self.timeObserver = self.avPlayer.addPeriodicTimeObserver(forInterval: CMTimeMake(value: 1,timescale: 2), queue: nil) { (time) in
            self.observer?.updateProgress(time: time.seconds)
            } as Any
    }

    func replaceURL(URL: URL, persistentID: UInt64) {
        // Remove notification from old player item
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer,
                                                      name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                                      object: self.playerItem)
        }

        // Create new player item
        self.playerItem             = AVPlayerItem(url: URL)
        self.playerItem.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithm.timeDomain
        createAudioFilterForPlayerItem()

        // Add notification to new player item
        if let observer = self.observer {
            NotificationCenter.default.addObserver(observer,
                                                   selector: #selector(Player.playbackFinished),
                                                   name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                                   object: self.playerItem)
        }

        self.persistentID           = persistentID
        self.seekingState           = .NotSeeking
        self.seekStartTime          = NSDate(timeIntervalSince1970: 0)
        self.requestedSeekTime      = nil

        self.avPlayer.replaceCurrentItem(with: self.playerItem)

        let status = self.avPlayer.status
        if status == AVPlayer.Status.unknown {
            self.playbackReadinessState = .Initialising
        }
        else if status == AVPlayer.Status.failed {
            self.playbackReadinessState = .Failed
        }
        else if status == AVPlayer.Status.readyToPlay {
            self.playbackReadinessState = .Ready
        }
        self.playbackRequestedState = .Nothing
    }

    deinit {
        if let observer = self.observer {
            // Remove time observer
            if let timeObserver = self.timeObserver {
                self.avPlayer.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }

            // Remove notification
            NotificationCenter.default.removeObserver(observer,
                                                      name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                                      object: self.playerItem)

            // Remove observers
            avPlayer.removeObserver(observer, forKeyPath: "rate")
            avPlayer.removeObserver(observer, forKeyPath: "status")
        }
    }

    func play() {
        if self.playbackReadinessState != .Ready {
            self.playbackRequestedState = .PlayRequested
            return
        }
        avPlayer.play()
    }

    func pause() {
        if self.playbackReadinessState != .Ready {
            self.playbackRequestedState = .PauseRequested
            return
        }
        avPlayer.pause()
    }

    func getCurrentTime() -> Double? {
        let time = avPlayer.currentTime()
        if time.isValid {
            return time.seconds
        }
        return nil
    }

    func getCurrentDuration() -> Double? {
        if let currentItem = avPlayer.currentItem {
            let duration = currentItem.duration
            if duration.isValid {
                return duration.seconds
            }
        }
        return nil
    }

    func stopSeeking() {
        // Stop seeking
        self.seekingState = .NotSeeking
        let currentTime = self.avPlayer.currentTime().seconds
        self.observer?.updateProgress(time: currentTime)
        self.observer?.configureNowPlayingInfoElapsedTime(elapsedTime: currentTime)
    }

    //static var debug = 1
    func setCurrentTime(time: Double) {
        // If we are not ready, store ths request until we are ready
        if self.playbackReadinessState != .Ready {
            self.requestedSeekTime = time
            return
        }

        // Start seeking
        self.seekingState = .Seeking
        self.seekStartTime = NSDate()
        //playerItem.asset.duration.timescale
        avPlayer.seek(to: CMTime(seconds: time, preferredTimescale: 600)) { (finished) in
            DispatchQueue.main.async {
                self.stopSeeking()
            }
        }
    }

    func didSeekRecently() -> Bool {
        let timeInterval: Double = self.seekStartTime.timeIntervalSinceNow
        if timeInterval < 0.5 {
            return true
        }
        return false
    }

    func isSeeking() -> Bool {
        return seekingState == .Seeking
    }
}

class Player : NSObject, Observer {
    static let sharedInstance = Player()

    var playingTrack: PlayingTrack? = nil
    var queue = PlayerQueue()

    var nowPlayingID: UInt64? {
        get {
            return playingTrack?.persistentID
        }
    }

    var indexNowPlaying: Int? {
        get {
            if playingTrack != nil {
                return queue.findTrackIndex(persistentID: playingTrack!.persistentID)
            }
            return nil
        }
    }

    func setQueue(items: [UInt64]) {
        queue.tracks.removeAll()
        for item in items {
            queue.tracks.append(PlayerTrack(persistentID: item))
        }
    }

    func configureNowPlayingInfo(item: MPMediaItem) {
        let info = MPNowPlayingInfoCenter.default()
        var newInfo: [String : Any] = [:]
        let itemProperties: Set<String>  = [MPMediaItemPropertyAlbumTitle,
                                            MPMediaItemPropertyAlbumTrackCount,
                                            MPMediaItemPropertyAlbumTrackNumber,
                                            MPMediaItemPropertyArtist,
                                            MPMediaItemPropertyArtwork,
                                            MPMediaItemPropertyComposer,
                                            MPMediaItemPropertyDiscCount,
                                            MPMediaItemPropertyDiscNumber,
                                            MPMediaItemPropertyGenre,
                                            MPMediaItemPropertyPersistentID,
                                            MPMediaItemPropertyPlaybackDuration,
                                            MPMediaItemPropertyTitle]

        for property in itemProperties {
            let propertyValue = item.value(forProperty: property)
            if (propertyValue != nil)
            {
                newInfo[property] = propertyValue
            }
        }

        newInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: 0.0)

        //print("now Playing Info (setting) = \(newInfo.debugDescription)")

        info.nowPlayingInfo = newInfo

        //print("now Playing Info (got)     = \(info.nowPlayingInfo.debugDescription)")
    }

    func configureNowPlayingInfoElapsedTime(elapsedTime: Double) {
        let info = MPNowPlayingInfoCenter.default()
        if info.nowPlayingInfo != nil {
            var newInfo = info.nowPlayingInfo!
            newInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: elapsedTime)
            info.nowPlayingInfo = newInfo
            //print("now Playing Info (elapsed time) = \(info.nowPlayingInfo.debugDescription)")
        }
    }

    @discardableResult
    func setTrack(persistentID: UInt64) -> Bool {
        // Get media item from persistent ID
        if let mediaItem = MusicLibrary.getMediaItems(itemIDs: [persistentID]).first {
            // Get asset URL from media item. NOTE: AssetURL can be nil for DRM/iCloud/partially downloaded tracks!
            if let assetURL = mediaItem.assetURL {
                // Create track using assetURL and start playing
                if playingTrack == nil {
                    playingTrack = PlayingTrack(URL: assetURL, persistentID: persistentID, observer: self)
                }
                else {
                    playingTrack?.replaceURL(URL: assetURL, persistentID: persistentID)
                }
                configureNowPlayingInfo(item: mediaItem)
                informObservers(reason: "updateTrack")
                isFastPlaying = false
                return true
            }
        }
        return false
    }

    @discardableResult 
    func play() -> Bool {
        //print("play") // TOBY
        // Play current track if we have one
        if playingTrack != nil {
            playingTrack?.play()
            return true
        }

        // If there's nothing in the queue to play, early out
        if queue.tracks.count == 0 {
            return false
        }

        // Play first item in queue
        if setTrack(persistentID: queue.tracks[0].persistentID) {
            playingTrack?.play()
            return true
        }

        // Failed to play the item
        return false
    }

    func pause() {
        //print("pause") // TOBY
        playingTrack?.pause()
        isFastPlaying = false
    }

    func togglePlayPause() {
        //print("togglePlayPause") // TOBY
        if playState() == .Playing {
            pause()
        }
        else {
            play()
        }
    }

    func stop() {
        //print("stop") // TOBY
        playingTrack?.pause()
        playingTrack = nil
        isFastPlaying = false
    }

    @discardableResult 
    func skipForwards(skipTime: Double = 30.0) -> Bool {
        //print("skipForwards") // TOBY
        if playState() == .Playing || playState() == .Paused {
            if let time = getCurrentTime() {
                let newTime = time + skipTime
                setCurrentTime(time: newTime)
                return true
            }
        }
        return false
    }

    @discardableResult
    func skipBackwards(skipTime: Double = 30.0) -> Bool {
        //print("skipBackwards") // TOBY
        if playState() == .Playing || playState() == .Paused {
            if let time = getCurrentTime() {
                let newTime = max(0.0, time - skipTime)
                setCurrentTime(time: newTime)
                return true
            }
        }
        return false
    }

    func playState() -> PlaybackState {
        if playingTrack == nil {
            return .Stopped
        }
        if playingTrack!.playbackReadinessState == .Failed {
            return .Failed
        }
        if playingTrack!.avPlayer.rate == 0 {
            return .Paused
        }

        return .Playing
    }

    func getCurrentTime() -> Double? {
        return playingTrack?.getCurrentTime()
    }

    func getCurrentDuration() -> Double? {
        return playingTrack?.getCurrentDuration()
    }

    func beginFastForwardPlay() {
        playingTrack?.avPlayer.rate = 5.0
        isFastPlaying = true
    }

    func beginFastBackwardPlay() {
        playingTrack?.avPlayer.rate = -5.0
        isFastPlaying = true
    }

    func endFastPlayback() {
        let time = playingTrack?.avPlayer.currentTime().seconds
        playingTrack?.avPlayer.rate = 1.0

        // Hack: reset current time after a short delay, otherwise playback tries to resume from the wrong place
        if time != nil {
            Utilities.delay(delay: 0.01) {
                self.setCurrentTime(time: time!)
            }
        }

        isFastPlaying = false
    }

    @discardableResult
    func skipToNextItem() -> Bool {
        guard let persistentID = playingTrack?.persistentID else { return false }
        guard let index = queue.findTrackIndex(persistentID: persistentID) else { return false }

        let nextIndex = index + 1
        if nextIndex < queue.tracks.count {
            setTrack(persistentID: queue.tracks[nextIndex].persistentID)
            play()
            return true
        }

        return false
    }

    @discardableResult
    func skipToPreviousItem() -> Bool {
        guard let persistentID = playingTrack?.persistentID else { return false }
        guard let index = queue.findTrackIndex(persistentID: persistentID) else { return false }

        if index > 0 {
            let prevIndex = index - 1
            setTrack(persistentID: queue.tracks[prevIndex].persistentID)
            play()
            return true
        }
        return false
    }

    @discardableResult
    func skipToBeginning() -> Bool {
        if queue.tracks.count > 0 {
            setTrack(persistentID: queue.tracks[0].persistentID)
            play()
            return true
        }
        return false
    }

    func setCurrentTime(time: Double) {
        playingTrack?.setCurrentTime(time: time)
    }

    func isSeeking() -> Bool {
        if playingTrack != nil && playingTrack!.isSeeking() {
            return true
        }
        return false
    }

    func didSeekRecently() -> Bool {
        if playingTrack != nil && playingTrack!.didSeekRecently() {
            return true
        }
        return false
    }

    func informObservers(reason: String, value: Double = 0.0) {
        // Inform observers on main thread
        DispatchQueue.main.async {
            self.propertyChanged(propertyName: reason, newValue: value, options:nil)
        }
    }

    @objc func playbackFinished() {
        // Find next track in queue
        //print("track finished!")

        for (trackIndex, track) in queue.tracks.enumerated() {
            if track.persistentID == self.playingTrack?.persistentID {
                let nextTrackIndex = trackIndex + 1
                if nextTrackIndex < queue.tracks.count {
                    let newTrackID = queue.tracks[nextTrackIndex].persistentID
                    //let time = dispatch_time(dispatch_time_t(DISPATCH_TIME_NOW), Int64(NSEC_PER_SEC / 10))
                    DispatchQueue.main.async {
                        let playerInstance = Player.sharedInstance
                        playerInstance.stop()
                        playerInstance.setTrack( persistentID: newTrackID )
                        playerInstance.play()
                    }
                    return
                }
            }
        }

        // Queue finished, cue up the first track again.
        if queue.tracks.first != nil {
            setTrack(persistentID: queue.tracks.first!.persistentID)
        }
        //print("queue finished!")
    }

    static var countUpdate: Int = 0

    func updateProgress(time: Double) {

        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        if appDelegate.isUIActive {
            //
            // App is in foreground
            //

            // Update bookmarks (and save them as needed)
            Bookmarks.updateBookmarks()

            // Inform observers to update UI
            //print("new Time is \(time)")
            informObservers(reason: "updateProgress")
        }
        else {
            //
            // App is in Background
            //

            // Update bookmarks at a lower frequency (once every 2 seconds, i.e. every fourth update call) to save energy
            if Player.countUpdate == 0 {
                Bookmarks.updateBookmarks()
                //print("new Time is \(time)")
                Player.countUpdate = 3
            }
            else {
                Player.countUpdate -= 1
            }
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?)
    {
        if context == &PlayingTrack.statusContext {
            // State has changed
            if let playingTrack = self.playingTrack {
                if playingTrack.avPlayer.status == .readyToPlay {
                    playingTrack.playbackReadinessState = .Ready
                    self.informObservers(reason: "readyToPlay")

                    // If we requested a seek time, do that now
                    if let seekTime = playingTrack.requestedSeekTime {
                        playingTrack.requestedSeekTime = nil
                        playingTrack.setCurrentTime(time: seekTime)
                    }

                    // If we requested playback, start playing
                    if playingTrack.playbackRequestedState == .PlayRequested {
                        playingTrack.playbackRequestedState = .Nothing
                        playingTrack.play()
                    }
                    else if playingTrack.playbackRequestedState == .PauseRequested {
                        playingTrack.playbackRequestedState = .Nothing
                        playingTrack.pause()
                    }
                    return
                }
                else if playingTrack.avPlayer.status == .failed {
                    playingTrack.playbackReadinessState = .Failed
                    self.informObservers(reason: "failed")
                    return
                }
                //print("#1a keyPath=\(keyPath), change=\(change), status = \(playingTrack.avPlayer.status.rawValue)")
                return
            }
            //print("#1b keyPath=\(keyPath), change=\(change), status = \(playingTrack?.avPlayer.status.rawValue)")
            return
        }
        if context == &PlayingTrack.rateContext {
            if let newValue = change?[NSKeyValueChangeKey(rawValue: "new")] as? NSNumber {
                self.informObservers(reason: "rateChanged", value: newValue.doubleValue)
                return
            }
            //print("#2 keyPath=\(keyPath), change=\(change)")
            return
        }
        //print("#3 keyPath=\(keyPath), change=\(change)")
        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }

    // --- Observer Protocol ---
    var subscribers: [Subscriber] = []

    func propertyChanged(propertyName: String, newValue: Double, options:[String:String]?){
        let matchingSubscribers = subscribers.filter({$0.properties.contains(propertyName)})
        matchingSubscribers.forEach({$0.notify(propertyValue: propertyName, newValue: newValue, options: options)})
    }

    func subscribe(subscriber: Subscriber){
        subscribers.append(subscriber)
    }

    func unsubscribe(subscriber: Subscriber) {
        subscribers = subscribers.filter({$0 !== subscriber})
    }
}

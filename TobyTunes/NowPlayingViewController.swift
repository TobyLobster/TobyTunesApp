//
//  NowPlayingViewController.swift
//  TobyTunes
//
//  Created by Toby Nelson on 14/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import UIKit
import MediaPlayer
import AVFoundation
import MarqueeLabel

enum PlayPauseButtonState {
    case Play
    case Pause
    case Undefined
}

class NowPlayingViewController: UIViewController, Subscriber {
    @IBOutlet weak var playPauseButton:     UIButton?
    @IBOutlet weak var forwardsButton:      UIButton?
    @IBOutlet weak var backwardsButton:     UIButton?
    @IBOutlet weak var bookmarkButton:      UIButton?
    @IBOutlet weak var progressSlider:      UISlider?
    @IBOutlet weak var artworkImageView:    UIImageView?
    @IBOutlet weak var artworkButtonImage:  UIImageView?
    @IBOutlet weak var backgroundImageView: UIImageView?
    @IBOutlet weak var titleLabel:          MarqueeLabel?
    @IBOutlet weak var albumLabel:          MarqueeLabel?
    @IBOutlet weak var artistLabel:         MarqueeLabel?
    @IBOutlet weak var volumeViewParent:    UIView?
    @IBOutlet weak var timeElapsedLabel:    UILabel?
    @IBOutlet weak var timeRemainingLabel:  UILabel?
    @IBOutlet weak var titleView:           UIView?
    @IBOutlet weak var titleHeightConstraint: NSLayoutConstraint?

    var volumeView : ALVolumeView? = nil
    //var timer : NSTimer?
    var dragging = false
    var songTitle : String = ""
    var thumbImage = UIImage(named: "sliderthumb")
    var cachedItem : MPMediaItem? = nil
    var cachedArtwork : MPMediaItemArtwork? = nil
    var pressingForward = false
    var pressingBackward = false
    var playButtonImage = PlayPauseButtonState.Undefined
    var fromTabIndex = 0

    override func viewDidLoad() {
        self.title = songTitle
        let backButton = UIBarButtonItem(title: "Back", style: UIBarButtonItemStyle.plain, target:self, action: #selector(back))
        self.navigationItem.leftBarButtonItem = backButton

        // Volume view
        volumeViewParent?.backgroundColor = UIColor.clear
        progressSlider?.setThumbImage(thumbImage, for: [])
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(changedTextSize), name: NSNotification.Name.UIContentSizeCategoryDidChange, object:nil)

        // gestures for fast forwards and backwards in a track
        forwardsButton?.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressForwards)))
        backwardsButton?.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressBackwards)))

        // Touch gesture on image
        artworkImageView?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(imageTap)))
        self.artworkButtonImage?.alpha = 0.0

        // Player observer
        Player.sharedInstance.subscribe(subscriber: self)
    }

    func changedTextSize() {
        self.titleLabel?.font           = Utilities.fontSized(originalSize: 17)
        self.albumLabel?.font           = Utilities.fontSized(originalSize: 17)
        self.artistLabel?.font          = Utilities.fontSized(originalSize: 17)
        self.timeElapsedLabel?.font     = Utilities.fontSized(originalSize: 17)
        self.timeRemainingLabel?.font   = Utilities.fontSized(originalSize: 17)
        let myString: NSString = "Xg" as NSString
        let size = myString.size(attributes: [NSFontAttributeName: Utilities.fontSized(originalSize: 17)!])
        let adjustedSize = CGSize(width: CGFloat(ceilf(Float(size.width))), height: CGFloat(ceilf(Float(size.height))))

        titleHeightConstraint?.constant = CGFloat(3.0 * adjustedSize.height + 6.0)
    }

    func back() {
        self.navigationController?.popViewController(animated: true)
        self.tabBarController?.selectedIndex = fromTabIndex
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        changedTextSize()

        registerMediaPlayerNotifications()
        registerOrientationChangeNotifications()

        updatePlaybackStateUI()
        updateCurrentTrackUI()
        updateProgressUI(dragging: false)
        //startTimer()

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        if (self.navigationController?.tabBarItem.tag == 1004) {
            self.navigationController?.tabBarItem.title = "Now Playing"
        }

        dragging = false
        pressingForward = false
        pressingBackward = false

        var selected = false
        if let currentTrackID: UInt64 = Player.sharedInstance.nowPlayingID {
            if Bookmarks.containsTrack(trackID: currentTrackID) {
                selected = true
            }
        }
        bookmarkButton?.isSelected = selected

        // change the back button to cancel and add an event handler
        // self.navigationController?.delegate
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        //stopTimer()
        dragging = false
        self.unregisterMediaPlayerNotifications()
        self.unregisterOrientationChangeNotifications()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        createVolumeView()
    }

    func registerMediaPlayerNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(musicLibraryUpdated),  name: NSNotification.Name.MPMediaLibraryDidChange, object: nil)
    }

    func unregisterMediaPlayerNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self, name: NSNotification.Name.MPMediaLibraryDidChange, object: nil)
    }

    func registerOrientationChangeNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(orientationChanged), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
    }

    func unregisterOrientationChangeNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self, name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
    }

    func musicLibraryUpdated() {
        updateCurrentTrackUI()
    }

    func orientationChanged( notification: NSNotification ) {
        if let volumeViewParent = volumeViewParent {
            Utilities.delay(delay: 0.1) {
                self.volumeView?.frame = volumeViewParent.bounds
                self.volumeView?.sizeToFit()
            }
        }
    }

    func createVolumeView() {
        if volumeView == nil {
            if let volumeViewParent = volumeViewParent {
                self.volumeView = ALVolumeView(frame: volumeViewParent.bounds)
                if let volumeView = self.volumeView {
                    volumeView.showsRouteButton = true
                    volumeView.setVolumeThumbImage(thumbImage, for: [])
                    volumeViewParent.addSubview(volumeView)
                    volumeView.sizeToFit()
                }
            }
        }
    }

    func updatePlaybackStateUI() {
        if let playPauseButton = playPauseButton {
            if Player.sharedInstance.playingTrack?.avPlayer.rate != 0 {
                if playButtonImage != .Pause {
                    playPauseButton.setImage(UIImage(named: "pause.pdf"), for: [])
                    playButtonImage = .Pause
                }
            }
            else {
                if playButtonImage != .Play {
                    playPauseButton.setImage(UIImage(named: "play.pdf"), for: [])
                    playButtonImage = .Play
                }
            }
        }
    }

    func updateCurrentTrackUI() {
        if let currentItemID = Player.sharedInstance.nowPlayingID {
            if cachedItem == nil || currentItemID != cachedItem!.persistentID {
                if let currentItem = MusicLibrary.getMediaItems(itemIDs: [currentItemID]).first {
                    cachedItem = currentItem
                    let artwork = currentItem.artwork
                    var artworkImage = MusicLibrary.resizeArtwork(artwork: artwork, fitWithinSize: CGSize(width: 320, height: 320))
                    var titleString = Utilities.safeGetString(string: currentItem.title)
                    let trackNumber = currentItem.albumTrackNumber

                    if (artworkImage == nil) {
                        artworkImage = UIImage(named: "logo")
                    }

                    artworkImageView?.image = artworkImage

                    if artworkImage != nil {
                        if artworkImageView != nil {
                            if (cachedArtwork != artwork) || (self.backgroundImageView?.image == nil) {
                                cachedArtwork = artwork
                                DispatchQueue.global(qos: .default).async {
                                    let blurImage = artworkImage!.imageWithGaussianBlur()

                                    DispatchQueue.main.async {
                                            self.backgroundImageView?.image = blurImage
                                        }
                                    }
                            }
                        }
                    }

                    if titleString != "" {
                        if trackNumber != 0 {
                            titleString = "\(trackNumber). \(titleString)"
                        }
                        titleLabel?.text = titleString
                    } else {
                        titleLabel?.text = "Unknown title"
                    }
                    titleLabel?.marqueeType = .MLContinuous
                    titleLabel?.scrollDuration = 6
                    titleLabel?.animationCurve = UIViewAnimationOptions.curveLinear
                    titleLabel?.fadeLength = 0.0
                    titleLabel?.animationDelay = 3.0
                    titleLabel?.trailingBuffer = 50.0

                    albumLabel?.marqueeType = .MLContinuous
                    albumLabel?.scrollDuration = 6
                    albumLabel?.animationCurve = UIViewAnimationOptions.curveLinear
                    albumLabel?.fadeLength = 0.0
                    albumLabel?.animationDelay = 3.0
                    albumLabel?.trailingBuffer = 50.0

                    artistLabel?.marqueeType = .MLContinuous
                    artistLabel?.scrollDuration = 6
                    artistLabel?.animationCurve = UIViewAnimationOptions.curveLinear
                    artistLabel?.fadeLength = 0.0
                    artistLabel?.animationDelay = 3.0
                    artistLabel?.trailingBuffer = 50.0

                    let artistString = Utilities.safeGetString(string: currentItem.artist)
                    if (artistString != "") {
                        artistLabel?.text = artistString
                    } else {
                        artistLabel?.text = "Unknown artist"
                    }

                    let albumString = Utilities.safeGetString(string: currentItem.albumTitle)
                    if albumString != "" {
                        albumLabel?.text = albumString
                    } else {
                        albumLabel?.text = "Unknown album"
                    }

                    if let doubleTime = Player.sharedInstance.getCurrentTime() {
                        progressSlider?.value = Float(doubleTime)
                        progressSlider?.minimumValue = 0
                        progressSlider?.maximumValue = Float(currentItem.playbackDuration)
                    }

                    updateProgressUI(dragging: dragging)
                }
            }
        }
        else {
            //artworkImageView?.image = nil
            titleLabel?.text = ""
            artistLabel?.text = ""
            albumLabel?.text = ""
            cachedItem = nil
        }
    }

    func progressString(progress : Double) -> String {
        let prog = max(progress, 0.0)
        let hour   = abs(Int(prog / 3600))
        let minute = abs(Int((prog / 60)) % 60)
        let second = abs(Int(prog) % 60)
        let secondString = second > 9 ? "\(second)" : "0\(second)"

        if hour > 0 {
            let minuteString = minute > 9 ? "\(minute)" : "0\(minute)"
            return "\(hour):\(minuteString):\(secondString)"
        }
        return "\(minute):\(secondString)"
    }

    func updateProgressUI(dragging drag : Bool) {
        var currentProgress : Double

        if let progressSlider = progressSlider {
            if drag {
                currentProgress = Double(progressSlider.value)
            }
            else {
                let time = Player.sharedInstance.getCurrentTime()
                if time == nil {
                    albumLabel?.text = "Stopped"
                    bookmarkButton?.isHidden = true
                    timeElapsedLabel?.text = ""
                    timeRemainingLabel?.text = ""
                    progressSlider.value = 0.0
                    return
                }
                currentProgress = time!
                if bookmarkButton != nil && bookmarkButton!.isHidden {
                    bookmarkButton?.isHidden = false
                }
            }

            // Bit of a hack to minimise glitchy seeking behaviour. Sometimes we get stuck in .Seeking state, so we break this
            if Player.sharedInstance.playState() != .Playing || !Player.sharedInstance.isSeeking() || !Player.sharedInstance.didSeekRecently() {
                // Set time elapsed label
                timeElapsedLabel?.text  = progressString(progress: currentProgress)

                // Set time remaining label
                let remaining           = Double(progressSlider.maximumValue) - currentProgress
                timeRemainingLabel?.text = "-" + progressString(progress: remaining)

                // Show current progress on slider
                progressSlider.value = CFloat(currentProgress)
            }
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        unregisterMediaPlayerNotifications()
    }

    func nextSongInternal() {
        Player.sharedInstance.skipToNextItem()
        updateCurrentTrackUI()
        updateProgressUI(dragging: false)
    }

    func previousSongInternal() {
        if Player.sharedInstance.indexNowPlaying! > 0 {
            Player.sharedInstance.skipToPreviousItem()
        }
        else {
            Player.sharedInstance.skipToBeginning()
        }
        updateCurrentTrackUI()
        updateProgressUI(dragging: false)
    }

    func forward30Internal() {
        if Player.sharedInstance.skipForwards() {
            updateProgressUI(dragging: false)
        }
    }

    func backward30Internal() {
        if Player.sharedInstance.skipBackwards() {
            updateProgressUI(dragging: false)
        }
    }

    func playPause() {
        if Player.sharedInstance.playState() == .Playing {
            Player.sharedInstance.pause()
            updatePlaybackStateUI()
        } else {
            Player.sharedInstance.play()
            updatePlaybackStateUI()
            updateProgressUI(dragging: false)
        }
    }

    func imageTap(recognizer: UITapGestureRecognizer) {
        playPause()

        var image: UIImage? = nil
        if Player.sharedInstance.playState() == .Playing {
            image = UIImage(named: "play")
        }
        else {
            image = UIImage(named: "pause")
        }

        if image != nil {
            self.artworkButtonImage?.alpha = 0.65
            self.artworkButtonImage?.image = image
            UIView.animate( withDuration: 0.7, animations: {
                self.artworkButtonImage?.alpha = 0.0
            })
        }
    }

    @IBAction func playPause(sender: UIButton) {
        playPause()
    }

    func longPressForwards(recognizer: UILongPressGestureRecognizer) {
        if (recognizer.state == .began) {
            if pressingForward == false {
                pressingForward = true
                Player.sharedInstance.beginFastForwardPlay()
            }
        }

        if (recognizer.state == .ended) ||
           (recognizer.state == .cancelled) ||
           (recognizer.state == .failed) {
            if pressingForward {
                Player.sharedInstance.endFastPlayback()
                pressingForward = false
            }
        }
    }

    func longPressBackwards(recognizer: UILongPressGestureRecognizer) {
        if (recognizer.state == .began) {
            if pressingBackward == false {
                pressingBackward = true
                Player.sharedInstance.beginFastBackwardPlay()
            }
        }

        if (recognizer.state == .ended) ||
            (recognizer.state == .cancelled) ||
            (recognizer.state == .failed) {
            if pressingBackward {
                Player.sharedInstance.endFastPlayback()
                pressingBackward = false
            }
        }
    }
    
    @IBAction func nextSong(sender: UIButton) {
        nextSongInternal()
    }

    @IBAction func previousSong(sender: UIButton) {
        previousSongInternal()
    }

    @IBAction func forward30ReleaseInside(sender: UIButton) {
        if pressingForward {
            Player.sharedInstance.endFastPlayback()
        }
        else {
            forward30Internal()
        }
        pressingForward = false
    }

    @IBAction func forward30ReleaseOutside(sender: UIButton) {
        if pressingForward {
            Player.sharedInstance.endFastPlayback()
            pressingForward = false
            updateProgressUI(dragging: false)
        }
    }

    @IBAction func back30ReleaseInside(sender: UIButton) {
        if pressingBackward {
            Player.sharedInstance.endFastPlayback()
        }
        else {
            backward30Internal()
        }
        pressingBackward = false
    }

    @IBAction func back30ReleaseOutside(sender: UIButton) {
        if pressingBackward {
            Player.sharedInstance.endFastPlayback()
            pressingBackward = false
            updateProgressUI(dragging: false)
        }
    }

    @IBAction func dragStart(sender: UISlider) {
        dragging = true
    }

    @IBAction func draggingInside(sender: UISlider) {
        updateProgressUI(dragging: true)
    }

    @IBAction func draggingOutside(sender: UISlider) {
        updateProgressUI(dragging: false)
    }

    @IBAction func dragStop(sender: UISlider) {
        dragging = false
        updateProgressUI(dragging: false)
    }

    @IBAction func slide(sender: UISlider) {
        dragging = false
        if progressSlider != nil {
            Player.sharedInstance.setCurrentTime(time: Double(progressSlider!.value))
            updateProgressUI(dragging: false)
            updateCurrentTrackUI()
        }
    }

    @IBAction func bookmark(sender: UIButton) {
        if sender.isSelected {
            if let currentTrackID: UInt64 = Player.sharedInstance.nowPlayingID {
                if let bookmarkId = Bookmarks.findBookmarkIdWithTrackID(persistentId: currentTrackID) {
                    Bookmarks.removeBookmark(bookmarkId: bookmarkId)
                }
            }
            sender.isSelected = false
        }
        else {
            if let currentTrackID = Player.sharedInstance.nowPlayingID {
                if let currentTrack = MusicLibrary.getMediaItems(itemIDs: [currentTrackID]).first {
                    // Is this track in the current playlist - if so, add a bookmark with the current playlist
                    if Bookmarks.isTrackIDInCurrentPlaylist(mediaItemID: currentTrackID) {
                        Bookmarks.addCurrentPlaylistAsBookmark()
                        sender.isSelected = true
                        return
                    }

                    // Is this track already bookmarked? If so, all is OK, just show the button marked
                    if Bookmarks.containsTrack(trackID: currentTrackID) {
                        sender.isSelected = true
                        return
                    }

                    // If this playlist is unknown, create a playlist of the current album and bookmark it
                    let albumID = currentTrack.albumPersistentID
                    let albumData = MusicLibrary.getSingleAlbumData(albumID: albumID)
                    if let repItem = albumData.representativeItem {
                        let artist = MusicLibrary.artistForItem(item: repItem)
                        let bookmarkTitle = Utilities.getAlbumDisplayName(album: albumData.representativeItem?.albumTitle)
                        let bookmarkDetails = Utilities.getArtistDisplayName(artist: artist)
                        Bookmarks.setCurrentPlaylist(type: .Album,
                                                     persistentID: albumID,
                                                     title: bookmarkTitle,
                                                     details: bookmarkDetails,
                                                     representativeItem: repItem,
                                                     mediaItems: albumData.items)
                        Bookmarks.addCurrentPlaylistAsBookmark()
                        sender.isSelected = true
                        return
                    }
                }
            }
        }
    }

    // Subscriber pattern:
    var properties = ["updateTrack", "updateProgress", "readyToPlay", "failed"]

    func notify(propertyValue: String, newValue: Double, options: [String:String]?) {
        updateCurrentTrackUI()
        updateProgressUI(dragging: dragging)
        updatePlaybackStateUI()
    }
}

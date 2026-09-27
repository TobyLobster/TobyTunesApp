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
    @IBOutlet weak var nextButton:          UIButton?
    @IBOutlet weak var previousButton:      UIButton?
    @IBOutlet weak var quietImageView:      UIImageView?
    @IBOutlet weak var loudImageView:       UIImageView?

    var volumeView : ALVolumeView? = nil
    //var timer : NSTimer?
    var dragging = false
    var songTitle : String = ""
    var thumbImage = NowPlayingViewController.makeSliderThumb()
    let backgroundGradient = CAGradientLayer()
    var hasArtworkColours = false
    var glassBackgrounds: [UIView] = []
    /// The Add to Playlist button at the top right (hidden when nothing is playing).
    var addToPlaylistButton: UIBarButtonItem? = nil
    /// Whether the "Nothing Playing" message is showing (nil until first checked).
    var showingNothingPlaying: Bool? = nil
    /// Shuffle on/off, on the right of the song titles (the bookmark button is on the left).
    let shuffleButton = UIButton(type: .custom)
    var cachedItem : MPMediaItem? = nil
    var cachedArtwork : MPMediaItemArtwork? = nil
    var pressingForward = false
    var pressingBackward = false
    var playButtonImage = PlayPauseButtonState.Undefined
    var fromTabIndex = 0

    override func viewDidLoad() {
        self.title = songTitle
        self.navigationItem.largeTitleDisplayMode = .never
        let backButton = UIBarButtonItem(title: "Back", style: UIBarButtonItem.Style.plain, target:self, action: #selector(back))
        self.navigationItem.leftBarButtonItem = backButton
        // About at the far right, as on the other tabs, with Add to Playlist beside it
        let aboutButton = UIBarButtonItem(image: UIImage(systemName: "info.circle"), style: .plain, target: self, action: #selector(showAbout))
        aboutButton.accessibilityLabel = "About"
        addToPlaylistButton = makeAddToPlaylistButton()
        self.navigationItem.rightBarButtonItems = [aboutButton, addToPlaylistButton!]

        // Volume view
        volumeViewParent?.backgroundColor = UIColor.clear
        progressSlider?.setThumbImage(thumbImage, for: [])
        applyNowPlayingStyle()
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(changedTextSize), name: UIContentSizeCategory.didChangeNotification, object:nil)

        // gestures for fast forwards and backwards in a track
        forwardsButton?.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressForwards)))
        backwardsButton?.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressBackwards)))

        // The play/pause overlay on the artwork is no longer used
        self.artworkButtonImage?.isHidden = true

        setUpShuffleButton()

        // Player observer
        Player.sharedInstance.subscribe(subscriber: self)
    }

    @objc func changedTextSize() {
        let titleFont  = Utilities.fontSized(originalSize: 20, weight: .bold) ?? UIFont.boldSystemFont(ofSize: 20)
        let detailFont = Utilities.fontSized(originalSize: 17) ?? UIFont.systemFont(ofSize: 17)
        let timeFont   = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium))
        self.titleLabel?.font           = titleFont
        self.albumLabel?.font           = detailFont
        self.artistLabel?.font          = detailFont
        self.timeElapsedLabel?.font     = timeFont
        self.timeRemainingLabel?.font   = timeFont

        // Title line, album and artist lines, and the 2pt gaps between them
        titleHeightConstraint?.constant = ceil(titleFont.lineHeight) + 2 * ceil(detailFont.lineHeight) + 6
    }

    /// "Add to Playlist" button at the top right: adds the playing song, or its whole album.
    func makeAddToPlaylistButton() -> UIBarButtonItem {
        // Worked out each time it's opened, as the playing song changes
        let menu = UIMenu(title: "", children: [UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.addToPlaylistMenuItems() ?? [])
        }])
        let button = UIBarButtonItem(title: nil, image: UIImage(systemName: "text.badge.plus"), primaryAction: nil, menu: menu)
        button.accessibilityLabel = "Add to Playlist"
        return button
    }

    func addToPlaylistMenuItems() -> [UIMenuElement] {
        guard let trackID = Player.sharedInstance.nowPlayingID,
              let item = MusicLibrary.getMediaItems(itemIDs: [trackID]).first else {
            return [UIAction(title: "Nothing Playing", attributes: .disabled) { _ in }]
        }
        let songName = Utilities.getTrackDisplayName(track: item.title)
        let song = UIAction(title: "Add Song to Playlist…", image: UIImage(systemName: "music.note")) { [weak self] _ in
            guard let self = self else { return }
            PlaylistActions.addToPlaylist(trackIDs: [trackID],
                                          summary: PlaylistActions.summary(name: songName, count: 1),
                                          from: self)
        }
        let albumItems = MusicLibrary.getSingleAlbumData(albumID: item.albumPersistentID).items
        let albumName = Utilities.getAlbumDisplayName(album: item.albumTitle)
        let album = UIAction(title: "Add Album to Playlist…", image: UIImage(systemName: "square.stack")) { [weak self] _ in
            guard let self = self else { return }
            PlaylistActions.addToPlaylist(trackIDs: albumItems.map { $0.persistentID },
                                          summary: PlaylistActions.summary(name: albumName, count: albumItems.count),
                                          from: self)
        }
        return [song, album]
    }

    /// With nothing loaded, the player controls are hidden and a message shows instead (like the one on
    /// Playlists when there are none), with buttons to go and choose something.
    func updateNothingPlayingState() {
        let nothingPlaying = Player.sharedInstance.nowPlayingID == nil
        if nothingPlaying {
            if showingNothingPlaying != true {
                for subview in view.subviews {
                    subview.alpha = 0
                }
            }
            // Set every time, as whether there are bookmarks can change
            contentUnavailableConfiguration = nothingPlayingConfiguration()
        }
        else if showingNothingPlaying != false {
            contentUnavailableConfiguration = nil
            for subview in view.subviews {
                subview.alpha = 1
            }
        }
        addToPlaylistButton?.isHidden = nothingPlaying
        showingNothingPlaying = nothingPlaying
    }

    func nothingPlayingConfiguration() -> UIContentUnavailableConfiguration {
        let hasBookmarks = Bookmarks.count() > 0
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: "music.note")
        configuration.imageProperties.tintColor = NowPlayingViewController.secondaryText
        configuration.text = "Nothing Playing"
        configuration.textProperties.color = .white
        configuration.secondaryText = hasBookmarks
            ? "Choose an album, artist or playlist to start listening, or carry on from a bookmark."
            : "Choose an album, artist or playlist to start listening."
        configuration.secondaryTextProperties.color = NowPlayingViewController.secondaryText

        // The deeper light-mode red, as for the bookmark and shuffle buttons on this dark screen
        var browse = UIButton.Configuration.filled()
        browse.title = "Browse Artists"
        browse.baseBackgroundColor = accentColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        browse.baseForegroundColor = .white
        browse.cornerStyle = .capsule
        configuration.button = browse
        configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in
            self?.showTab(titled: "Artists")
        }

        if hasBookmarks {
            var bookmarks = UIButton.Configuration.plain()
            bookmarks.title = "Open Bookmarks"
            bookmarks.baseForegroundColor = .white
            configuration.secondaryButton = bookmarks
            configuration.secondaryButtonProperties.primaryAction = UIAction { [weak self] _ in
                self?.showTab(titled: "Bookmarks")
            }
        }
        return configuration
    }

    /// Opens About as a sheet (it follows the phone's light/dark setting, not this dark screen).
    @objc func showAbout() {
        (tabBarController as? TTTabBarController)?.showAbout()
    }

    func showTab(titled title: String) {
        guard let tabBarController = tabBarController,
              let index = tabBarController.viewControllers?.firstIndex(where: { $0.tabBarItem.title == title }) else { return }
        tabBarController.selectedIndex = index
    }

    /// Adds the shuffle button to the song titles area, mirroring the bookmark button on the other side.
    func setUpShuffleButton() {
        guard let titlesView = bookmarkButton?.superview, let bookmarkButton = bookmarkButton else { return }
        let side: CGFloat = 50
        shuffleButton.frame = CGRect(x: 0, y: 0, width: side, height: side)
        shuffleButton.translatesAutoresizingMaskIntoConstraints = false
        titlesView.addSubview(shuffleButton)
        NSLayoutConstraint.activate([
            shuffleButton.trailingAnchor.constraint(equalTo: titlesView.trailingAnchor),
            shuffleButton.centerYAnchor.constraint(equalTo: bookmarkButton.centerYAnchor),
            shuffleButton.widthAnchor.constraint(equalToConstant: side),
            shuffleButton.heightAnchor.constraint(equalToConstant: side),
        ])

        // White when off; the accent colour when on (the deeper light-mode red, as for a bookmark)
        let onColour = accentColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let offImage = NowPlayingViewController.symbol("shuffle", size: 21)
        let onImage = NowPlayingViewController.symbol("shuffle", size: 21, weight: .bold, colour: onColour)
        shuffleButton.setImage(offImage, for: .normal)
        shuffleButton.setImage(onImage, for: .selected)
        shuffleButton.setImage(onImage, for: [.selected, .highlighted])
        shuffleButton.accessibilityLabel = "Shuffle"
        shuffleButton.addTarget(self, action: #selector(toggleShuffle), for: .touchUpInside)
        addGlassBackground(to: shuffleButton)
        updateShuffleButton()
    }

    func updateShuffleButton() {
        shuffleButton.isSelected = Player.sharedInstance.isShuffled
        shuffleButton.accessibilityValue = Player.sharedInstance.isShuffled ? "On" : "Off"
    }

    /// Shuffle on: the playing song carries on and the rest of the list follows in a random order.
    /// Shuffle off: back to the list's normal order, carrying on from the playing song.
    @objc func toggleShuffle() {
        let turningOn = !Player.sharedInstance.isShuffled
        let sheet = UIAlertController(
            title: turningOn ? "Shuffle?" : "Turn Off Shuffle?",
            message: turningOn ? "This song carries on, then the rest play in a random order."
                               : "Carries on from this song in the normal order.",
            preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: turningOn ? "Shuffle" : "Turn Off Shuffle", style: .default) { [weak self] _ in
            Player.sharedInstance.setShuffle(turningOn)
            self?.updateShuffleButton()
            // A bookmark for this list remembers the new order straight away
            Bookmarks.updateBookmarks()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        // iPad shows it as a popover from the button
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = shuffleButton
            popover.sourceRect = shuffleButton.bounds
        }
        present(sheet, animated: true, completion: nil)
    }

    @objc func back() {
        self.navigationController?.popViewController(animated: true)
        self.tabBarController?.selectedIndex = fromTabIndex
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateNothingPlayingState()

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

        // Bookmarked when the list being played has a bookmark
        bookmarkButton?.isSelected = Player.sharedInstance.nowPlayingID != nil && Bookmarks.currentBookmarkId != nil
        // Dimmed and unavailable when the playlist being played has been deleted
        let canBookmark = Bookmarks.canBookmarkCurrentPlaylist
        bookmarkButton?.isEnabled = canBookmark
        bookmarkButton?.alpha = canBookmark ? 1.0 : 0.35
        updateShuffleButton()

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
        notificationCenter.addObserver(self, selector: #selector(orientationChanged), name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    func unregisterOrientationChangeNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    @objc func musicLibraryUpdated() {
        updateCurrentTrackUI()
    }

    @objc func orientationChanged( notification: NSNotification ) {
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
                    volumeView.setVolumeThumbImage(thumbImage, for: [])
                    volumeView.tintColor = .white
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
                    playPauseButton.setImage(NowPlayingViewController.symbol("pause.fill", size: 36), for: [])
                    playButtonImage = .Pause
                }
            }
            else {
                if playButtonImage != .Play {
                    playPauseButton.setImage(NowPlayingViewController.symbol("play.fill", size: 36), for: [])
                    playButtonImage = .Play
                }
            }
        }
    }

    func updateCurrentTrackUI() {
        updateNothingPlayingState()
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

                    if let image = artworkImage, (cachedArtwork != artwork) || !hasArtworkColours {
                        cachedArtwork = artwork
                        let itemID = currentItemID
                        DispatchQueue.global(qos: .userInitiated).async {
                            let colours = ArtworkColours.gradient(for: image)
                            DispatchQueue.main.async {
                                // Ignore a result for a track that's no longer playing (skipping quickly)
                                guard self.cachedItem?.persistentID == itemID else { return }
                                self.setBackground(top: colours.top, bottom: colours.bottom, animated: true)
                                self.hasArtworkColours = true
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
                    titleLabel?.type = .continuous
                    titleLabel?.speed = .duration(6)
                    titleLabel?.animationCurve = .linear
                    titleLabel?.fadeLength = 0.0
                    titleLabel?.animationDelay = 3.0
                    titleLabel?.trailingBuffer = 50.0

                    albumLabel?.type = .continuous
                    albumLabel?.speed = .duration(6)
                    albumLabel?.animationCurve = .linear
                    albumLabel?.fadeLength = 0.0
                    albumLabel?.animationDelay = 3.0
                    albumLabel?.trailingBuffer = 50.0

                    artistLabel?.type = .continuous
                    artistLabel?.speed = .duration(6)
                    artistLabel?.animationCurve = .linear
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
                    shuffleButton.isHidden = true
                    timeElapsedLabel?.text = ""
                    timeRemainingLabel?.text = ""
                    progressSlider.value = 0.0
                    return
                }
                currentProgress = time!
                if bookmarkButton != nil && bookmarkButton!.isHidden {
                    bookmarkButton?.isHidden = false
                }
                if shuffleButton.isHidden {
                    shuffleButton.isHidden = false
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
        if (Player.sharedInstance.indexNowPlaying ?? 0) > 0 {
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

    @IBAction func playPause(sender: UIButton) {
        playPause()
    }

    @objc func longPressForwards(recognizer: UILongPressGestureRecognizer) {
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

    @objc func longPressBackwards(recognizer: UILongPressGestureRecognizer) {
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
        // Nothing to bookmark when the playlist being played has been deleted
        guard sender.isSelected || Bookmarks.canBookmarkCurrentPlaylist else { return }
        if sender.isSelected {
            // Remove the bookmark for the list being played
            if let bookmarkId = Bookmarks.currentBookmarkId {
                Bookmarks.removeBookmark(bookmarkId: bookmarkId)
            }
            else if let currentTrackID: UInt64 = Player.sharedInstance.nowPlayingID,
                    let bookmarkId = Bookmarks.findBookmarkIdWithTrackID(persistentId: currentTrackID) {
                Bookmarks.removeBookmark(bookmarkId: bookmarkId)
            }
            sender.isSelected = false
        }
        else {
            if let currentTrackID = Player.sharedInstance.nowPlayingID {
                if let currentTrack = MusicLibrary.getMediaItems(itemIDs: [currentTrackID]).first {
                    // Is this track in the current playlist - if so, add a bookmark with the current playlist
                    if Bookmarks.isTrackIDInCurrentPlaylist(mediaItemID: currentTrackID) {
                        Bookmarks.addCurrentPlaylistAsBookmark()
                        sender.isSelected = Bookmarks.currentBookmarkId != nil
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
    var properties = ["updateTrack", "updateProgress", "readyToPlay", "failed", "updateShuffle"]

    func notify(propertyValue: String, newValue: Double, options: [String:String]?) {
        if propertyValue == "updateShuffle" {
            updateShuffleButton()
            return
        }
        updateCurrentTrackUI()
        updateProgressUI(dragging: dragging)
        updatePlaybackStateUI()
    }
}

// MARK: - Appearance

extension NowPlayingViewController {
    static let secondaryText = UIColor.white.withAlphaComponent(0.72)

    /// A white SF Symbol at `size` points.
    static func symbol(_ name: String, size: CGFloat, weight: UIImage.SymbolWeight = .semibold, colour: UIColor = .white) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: weight)
        return UIImage(systemName: name, withConfiguration: config)?.withTintColor(colour, renderingMode: .alwaysOriginal)
    }

    /// Thumb for the progress and volume sliders (shared with the About screen).
    static func makeSliderThumb() -> UIImage {
        return Utilities.sliderThumbImage()
    }

    func applyNowPlayingStyle() {
        // Background: a gradient taken from the artwork (replaces the old blurred image)
        backgroundImageView?.isHidden = true
        view.backgroundColor = ArtworkColours.defaultGradient.bottom
        backgroundGradient.startPoint = CGPoint(x: 0.5, y: 0)
        backgroundGradient.endPoint = CGPoint(x: 0.5, y: 1)
        view.layer.insertSublayer(backgroundGradient, at: 0)
        setBackground(top: ArtworkColours.defaultGradient.top, bottom: ArtworkColours.defaultGradient.bottom, animated: false)

        // Text
        titleLabel?.textColor = .white
        albumLabel?.textColor = NowPlayingViewController.secondaryText
        artistLabel?.textColor = NowPlayingViewController.secondaryText
        timeElapsedLabel?.textColor = NowPlayingViewController.secondaryText
        timeRemainingLabel?.textColor = NowPlayingViewController.secondaryText

        // Artwork: rounded corners, filled edge to edge, with a soft shadow from its container
        artworkImageView?.contentMode = .scaleAspectFill
        artworkImageView?.layer.cornerRadius = 14
        artworkImageView?.layer.cornerCurve = .continuous
        artworkImageView?.clipsToBounds = true
        if let container = artworkImageView?.superview {
            container.clipsToBounds = false
            container.layer.shadowColor = UIColor.black.cgColor
            container.layer.shadowOpacity = 0.45
            container.layer.shadowRadius = 20
            container.layer.shadowOffset = CGSize(width: 0, height: 12)
        }
        artworkButtonImage?.contentMode = .center

        // Transport controls
        previousButton?.setImage(NowPlayingViewController.symbol("backward.end.fill", size: 28), for: [])
        backwardsButton?.setImage(NowPlayingViewController.symbol("gobackward.30", size: 31, weight: .medium), for: [])
        forwardsButton?.setImage(NowPlayingViewController.symbol("goforward.30", size: 31, weight: .medium), for: [])
        nextButton?.setImage(NowPlayingViewController.symbol("forward.end.fill", size: 28), for: [])
        previousButton?.accessibilityLabel = "Previous track"
        backwardsButton?.accessibilityLabel = "Back 30 seconds"
        forwardsButton?.accessibilityLabel = "Forward 30 seconds"
        nextButton?.accessibilityLabel = "Next track"
        playPauseButton?.accessibilityLabel = "Play or pause"
        if let playPauseButton = playPauseButton {
            addGlassBackground(to: playPauseButton)
        }

        // Bookmark button: white outline when not bookmarked; accent-coloured with a tick when it is
        if let bookmarkButton = bookmarkButton {
            bookmarkButton.backgroundColor = .clear
            bookmarkButton.setImage(NowPlayingViewController.symbol("bookmark", size: 24), for: .normal)
            let bookmarked = NowPlayingViewController.bookmarkedImage()
            bookmarkButton.setImage(bookmarked, for: .selected)
            bookmarkButton.setImage(bookmarked, for: [.selected, .highlighted])
            bookmarkButton.accessibilityLabel = "Bookmark"
            addGlassBackground(to: bookmarkButton)
        }

        // Progress slider: slim white track
        progressSlider?.minimumTrackTintColor = .white
        progressSlider?.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)

        // Volume icons
        quietImageView?.image = NowPlayingViewController.symbol("speaker.fill", size: 13, colour: NowPlayingViewController.secondaryText)
        loudImageView?.image = NowPlayingViewController.symbol("speaker.wave.3.fill", size: 13, colour: NowPlayingViewController.secondaryText)
        quietImageView?.contentMode = .center
        loudImageView?.contentMode = .center

        // Transparent navigation bar with white text over the gradient
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.leftBarButtonItem?.tintColor = .white
        for item in navigationItem.rightBarButtonItems ?? [] {
            item.tintColor = .white
        }
    }

    /// Bookmark icon for "bookmarked": a filled bookmark in the accent colour with a white tick on it.
    static func bookmarkedImage() -> UIImage? {
        let size: CGFloat = 24
        guard let bookmark = UIImage(systemName: "bookmark.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .semibold)),
              let tick = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.5, weight: .heavy)) else {
            return symbol("bookmark.fill", size: size)
        }
        // The deeper light-mode red: stands out on the dark background and keeps the white tick crisp
        let fill = accentColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let renderer = UIGraphicsImageRenderer(size: bookmark.size)
        let image = renderer.image { _ in
            bookmark.withTintColor(fill, renderingMode: .alwaysOriginal).draw(at: .zero)
            // Tick centred slightly above the middle, clear of the bookmark's notch
            let tickOrigin = CGPoint(x: (bookmark.size.width - tick.size.width) / 2,
                                     y: (bookmark.size.height - tick.size.height) / 2 - bookmark.size.height * 0.08)
            tick.withTintColor(.white, renderingMode: .alwaysOriginal).draw(at: tickOrigin)
        }
        return image.withRenderingMode(.alwaysOriginal)
    }

    /// Circular backing behind a button: Liquid Glass on iOS 26, a translucent disc before that.
    func addGlassBackground(to button: UIButton) {
        let backing: UIView
        if #available(iOS 26.0, *) {
            backing = UIVisualEffectView(effect: UIGlassEffect())
        } else {
            backing = UIView()
            backing.backgroundColor = UIColor.white.withAlphaComponent(0.16)
            backing.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
            backing.layer.borderWidth = 0.5
        }
        backing.isUserInteractionEnabled = false
        backing.clipsToBounds = true
        backing.frame = button.bounds
        backing.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.insertSubview(backing, at: 0)
        glassBackgrounds.append(backing)
    }

    func setBackground(top: UIColor, bottom: UIColor, animated: Bool) {
        let colours = [top.cgColor, bottom.cgColor]
        if animated {
            let fade = CABasicAnimation(keyPath: "colors")
            fade.fromValue = backgroundGradient.colors
            fade.toValue = colours
            fade.duration = 0.5
            backgroundGradient.add(fade, forKey: "colors")
        }
        backgroundGradient.colors = colours
        view.backgroundColor = bottom
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundGradient.frame = view.bounds
        CATransaction.commit()

        for backing in glassBackgrounds {
            backing.layer.cornerRadius = min(backing.bounds.width, backing.bounds.height) / 2
            if let button = backing.superview as? UIButton, let imageView = button.imageView {
                button.bringSubviewToFront(imageView)
            }
        }

        if let artwork = artworkImageView, let container = artwork.superview {
            container.layer.shadowPath = UIBezierPath(roundedRect: artwork.frame, cornerRadius: 14).cgPath
        }

        spaceOutTransportControls()
    }

    /// Spreads the five transport buttons as far apart as the controls row allows, up to 24pt
    /// between them (easier to hit), but never less than the original 9pt on narrow phones.
    /// The play button stays centred; the gaps are the storyboard's button-to-button constraints.
    func spaceOutTransportControls() {
        let buttons = [previousButton, backwardsButton, playPauseButton, forwardsButton, nextButton].compactMap { $0 }
        guard buttons.count == 5, let row = playPauseButton?.superview, row.bounds.width > 0 else { return }

        let buttonWidths = buttons.reduce(CGFloat(0)) { $0 + $1.bounds.width }
        let spacing = max(9, min(24, floor((row.bounds.width - buttonWidths) / 4)))

        for constraint in row.constraints where constraint.firstAttribute == .leading && constraint.secondAttribute == .trailing {
            let joinsTwoButtons = buttons.contains { $0 === constraint.firstItem } && buttons.contains { $0 === constraint.secondItem }
            if joinsTwoButtons && constraint.constant != spacing {
                constraint.constant = spacing
            }
        }
    }
}

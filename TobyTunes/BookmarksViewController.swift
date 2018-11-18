//
//  BookmarksViewController.swift
//  TobyTunes
//
//  Created by Toby Nelson on 14/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import UIKit
import MediaPlayer

class BookmarksViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout, RZCollectionTableViewLayoutDelegate, Subscriber /*UIGestureRecognizerDelegate*/ {

    let CellIdentifier = "Cell"
    var columns = 1
    var needsRecalculation = false
    var rowToTransitionTo = -1
    var registeredForNotifications = false
    //var bookmarkData: BookmarkData = BookmarkData()

    func titleString(dataIndex: Int) -> String {
        if let playlist = Bookmarks.getBookmarkAtIndex(index: dataIndex)?.playlist {
            return playlist.title
        }
        return ""
    }

    func detailsString(dataIndex: Int) -> String {
        if let playlist = Bookmarks.getBookmarkAtIndex(index: dataIndex)?.playlist {
            return playlist.details
        }
        return ""
    }

    func sizeForCell(dataIndex: Int) -> CGSize {
        let title   = titleString(dataIndex: dataIndex)
        let details = detailsString(dataIndex: dataIndex)
        guard let collectionView = collectionView else { return CGSize.zero }
        let maxWidth = collectionView.frame.size.width
        let width    = floor(maxWidth / CGFloat(columns))
        let padding  = CGFloat(8+thumbnailWidth+10+10+80)

        let titleSize   = Utilities.measureText(text: title, attributes: Utilities.textTitleAttributes(), width: width - padding + 2)
        let detailsSize = Utilities.measureText(text: details, attributes: Utilities.textDetailsAttributes())

        return CGSize(width: width, height: max(CGFloat(thumbnailHeight), ceil(titleSize.height) + ceil(detailsSize.height)) + 10)
    }

    func tableIndexToDataIndex(tableIndex: Int) -> Int {
        return Utilities.tableIndexToDataIndex(tableIndex: tableIndex, columns: columns, total: Bookmarks.count() )
    }

    func dataIndexToTableIndex(dataIndex: Int) -> Int {
        return Utilities.dataIndexToTableIndex(dataIndex: dataIndex, columns: columns, total: Bookmarks.count() )
    }

    // --- Collection View ---
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let firstInRow = Int(indexPath.row / columns) * columns
        var totalSize = CGSize.zero
        for i in firstInRow..<(firstInRow+columns) {
            if i < Bookmarks.count() {
                let size = sizeForCell(dataIndex: tableIndexToDataIndex(tableIndex: i))
                totalSize = CGSize(width: max(size.width, totalSize.width), height: max(size.height, totalSize.height))
            }
        }
        return totalSize
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return Bookmarks.count()
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CellIdentifier, for: indexPath)
        if let cell = cell as? TTBookmarkCollectionViewCell {
            let dataIndex = tableIndexToDataIndex(tableIndex: indexPath.row)

            cell.bookmarkName?.text = titleString(dataIndex: dataIndex)
            cell.bookmarkDetails?.text = detailsString(dataIndex: dataIndex)

            if let mark = Bookmarks.getBookmarkAtIndex(index: dataIndex) {
                let playlist = mark.playlist

                cell.bookmarkArt?.image = UIImage(named: "logo44")
                cell.bookmarkPlay?.tag = mark.id
                cell.tag = mark.id

                let items = MusicLibrary.getMediaItems(itemIDs: [playlist.representativeItemID])
                if items.count > 0 {
                    let artwork      = items[0].artwork
                    let artworkImage = MusicLibrary.resizeArtwork(artwork: artwork, fitWithinSize: thumbnailSize)
                    if artworkImage != nil {
                        let artWithBorders = artworkImage!.imageWithBorders(width: thumbnailWidth, height: thumbnailHeight)
                        cell.bookmarkArt?.image = artWithBorders
                    }
                }
                cell.bookmarkName?.font = Utilities.fontSized(originalSize: 17)
                cell.bookmarkDetails?.font = Utilities.fontSized(originalSize: 15)
                cell.bookmarkPlay?.titleLabel?.font = Utilities.fontSized(originalSize: 15)

                let fullWidth = cell.frame.width - 55
                if let bookmark = Bookmarks.getBookmarkAtIndex(index: dataIndex) {

                    // Update progress width constraint
                    if bookmark.playlist.totalDuration > 0 {
                        let progress = bookmark.elapsedTime() / bookmark.playlist.totalDuration
                        cell.bookmarkWidthConstraint?.constant = CGFloat(-8 + ((1.0-progress) * Double(fullWidth)))
                    }

                    var currentlyPlayingIndex = -1
                    if let nowPlayingID = Player.sharedInstance.nowPlayingID {
                        if bookmark.containsTrackID( trackID: nowPlayingID ) {
                            currentlyPlayingIndex = indexPath.row
                        }
                    }

                    cell.backgroundColor = Utilities.cellBackgroundColor(indexPath: indexPath, currentlyPlayingTableIndex: currentlyPlayingIndex)
                }
                //if let oldFrame = cell.bookmarkProgress?.frame {
                //    let newFrame = CGRect(x: oldFrame.minX, y: oldFrame.minY, width: collectionView.frame.width, height: oldFrame.height)
                //    cell.bookmarkProgress?.frame = newFrame
                //}


                // "Selected" state
                //let backgroundView = UIView()
                //backgroundView.backgroundColor = UIColor(red: 0.0/255.0, green:0.0/255.0, blue:0.0/255.0, alpha:15/255.0)
                //cell.selectedBackgroundView = backgroundView
            }
        }
        return cell
    }

    static var initialTranslationX = CGFloat(0.0)

    @IBAction func handleCellPressed(sender: UIButton) {
        if let bookmark = Bookmarks.findMarkWithId(bookmarkId: sender.tag) {
            // Create the action sheet
            let myActionSheet = UIAlertController(title: bookmark.playlist.title, message: bookmark.playlist.details, preferredStyle: UIAlertControllerStyle.actionSheet)
            
            // Resume action button
            let resumeAction = UIAlertAction(title: "Resume Playback", style: UIAlertActionStyle.default) { (action) in
                self.performSegue(withIdentifier: "ResumePlayback", sender: sender)
            }

            // Play From Start action button
            let restartAction = UIAlertAction(title: "Play From Start", style: UIAlertActionStyle.default) { (action) in
                // Set bookmark back to start
                Bookmarks.resetBookmark(bookmarkId: sender.tag)

                // Go to now playing scene, and play the track
                self.performSegue(withIdentifier: "ResumePlayback", sender: sender)
            }

            // Delete action button
            let deleteAction = UIAlertAction(title: "Delete Bookmark", style: UIAlertActionStyle.default) { (action) in
                // Remove data item
                if let index = Bookmarks.removeBookmark(bookmarkId: sender.tag) {
                    //self.bookmarkData = Bookmarks.getBookmarkData()
                    self.needsRecalculation = true
                    self.rowToTransitionTo = -1

                    // Tell collection view to update
                    self.collectionView?.deleteItems(at: [IndexPath(row: index, section: 0)])
                }
            }

            // cancel action button
            let cancelAction = UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel) { (action) in
                // Do Nothing
            }
            // add action buttons to action sheet
            myActionSheet.addAction(resumeAction)
            myActionSheet.addAction(restartAction)
            myActionSheet.addAction(deleteAction)
            myActionSheet.addAction(cancelAction)

            // support iPads (popover view)
            if let popOver = myActionSheet.popoverPresentationController {
                popOver.sourceView  = sender as UIView
                popOver.sourceRect = (sender as UIView).bounds
                popOver.permittedArrowDirections = UIPopoverArrowDirection.any
            }

            // present the action sheet
            self.present(myActionSheet, animated: true, completion: nil)
        }
    }

    // --- Segue ---
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.destination is NowPlayingNavigationController {
            // Play all in playlist
            guard let view = sender as? UIView else { return }
            if let bookmark = Bookmarks.findMarkWithId(bookmarkId: view.tag) {
                let itemIDs          = bookmark.playlist.mediaItemIDs
                if itemIDs.count > 0 {
                    let items = MusicLibrary.getMediaItems(itemIDs: itemIDs)

                    var startPosition : TimeInterval = 0.0
                    var songTrack: MPMediaItem? = nil

                    // Set the current track and track time based on the bookmark
                    if bookmark.currentItemIndex < items.count {
                        startPosition = bookmark.currentTrackTime
                        songTrack = items[bookmark.currentItemIndex]

                        Player.sharedInstance.pause()
                        Player.sharedInstance.setQueue(items: items.map({$0.persistentID}))
                        Player.sharedInstance.setTrack(persistentID: songTrack!.persistentID)
                        Player.sharedInstance.setCurrentTime(time: startPosition)
                        Player.sharedInstance.play()
                    }
                }
            }
        }
    }

    // --- View ---
    override func viewDidLoad() {
        super.viewDidLoad()
        let bgColourView = UIView()
        bgColourView.backgroundColor = UIColor.white
        self.collectionView?.backgroundView = bgColourView

        Player.sharedInstance.subscribe(subscriber: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.navigationItem.title = "Bookmarks"
        //bookmarkData = Bookmarks.getBookmarkData()
        needsRecalculation = true
        rowToTransitionTo = -1
        self.collectionView?.reloadData()

        registerForNotifications()
        updatePlaybackItemUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if needsRecalculation {
            recalculateColumns(size: self.view.frame.size)
            if rowToTransitionTo >= 0 {
                let indexPath = IndexPath(row: rowToTransitionTo, section: 0)
                self.collectionView?.scrollToItem(at: indexPath, at: .bottom, animated: false)
            }
            needsRecalculation = false
            rowToTransitionTo = -1
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        //unregisterForNotifications()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        let visibleItems = self.collectionView?.indexPathsForVisibleItems
        rowToTransitionTo = -1

        if let visibleItems = visibleItems {
            for v in visibleItems {
                rowToTransitionTo = max(rowToTransitionTo, v.row)
            }
        }
        needsRecalculation = true
    }

    func registerForNotifications() {
        if !registeredForNotifications {
            let notificationCenter = NotificationCenter.default
            notificationCenter.addObserver(self, selector: #selector(musicLibraryUpdated),  name: NSNotification.Name.MPMediaLibraryDidChange, object: nil)
            notificationCenter.addObserver(self, selector: #selector(changedTextSize), name: NSNotification.Name.UIContentSizeCategoryDidChange, object:nil)

            MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
            registeredForNotifications = true
        }
    }

    func unregisterForNotifications() {
        if registeredForNotifications {
            let notificationCenter = NotificationCenter.default
            notificationCenter.removeObserver(self, name: NSNotification.Name.UIContentSizeCategoryDidChange, object: nil)
            notificationCenter.removeObserver(self, name: NSNotification.Name.MPMediaLibraryDidChange, object: nil)

            MPMediaLibrary.default().endGeneratingLibraryChangeNotifications()
            registeredForNotifications = false
        }
    }

    func musicLibraryUpdated() {
        //bookmarkData = Bookmarks.getBookmarkData()
        collectionView?.reloadData()
        updatePlaybackItemUI()
    }

    func changedTextSize() {
        collectionView?.reloadData()
    }

    func updateRows(oldRow: Int, newRow: Int) {
        if oldRow >= 0 {
            collectionView?.reloadItems(at: [IndexPath(row: oldRow, section: 0)])
        }
        if newRow >= 0 {
            collectionView?.reloadItems(at: [IndexPath(row: newRow, section: 0)])
        }
    }

    func updatePlaybackItemUI() {
        // TODO
    }

    func recalculateColumns(size: CGSize) {
        let minColumnWidthInches = 2.0
        columns = Utilities.recalculateColumns(size: size, minColumnWidthInches: minColumnWidthInches)
        self.collectionView?.reloadData()
    }

    // Subscriber pattern:
    var properties = ["updateTrack"]

    func notify(propertyValue: String, newValue: Double, options: [String:String]?) {
        updatePlaybackItemUI()
    }
}

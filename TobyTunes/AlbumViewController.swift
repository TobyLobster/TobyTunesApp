//
//  AlbumViewController.swift
//  TobyTunes
//
//  Created by Toby Nelson on 14/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import UIKit
import MediaPlayer

class AlbumViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout, Subscriber {

    let CellIdentifier          = "Cell"
    var genreTitle: String?     = nil
    var artistTitle             = ""
    var albumTitle              = ""
    var singleAlbumData = SingleAlbumData(items: [], representativeItem: nil)
    var currentlyPlayingDataIndex = -1
    var columns = 1
    var needsRecalculation = false
    var rowToTransitionTo = -1
    var registeredForNotifications = false

    func titleString(dataIndex: Int) -> String {
        let item         = singleAlbumData.items[dataIndex]
        let trackNumber  = item.albumTrackNumber
        let songTitle    = Utilities.getTrackDisplayName(track: item.title)

        if (trackNumber != 0) {
            return "\(trackNumber). \(songTitle)"
        } else {
            return "\(songTitle)"
        }
    }

    func detailsString(dataIndex: Int) -> String {
        let item         = singleAlbumData.items[dataIndex]
        let songDuration = item.playbackDuration as NSNumber
        return "\(Utilities.timeIntervalStringDHMSStyle(duration: songDuration.doubleValue))"
    }

    func tableIndexToDataIndex(tableIndex: Int) -> Int {
        return Utilities.tableIndexToDataIndex(tableIndex: tableIndex, columns: columns, total: singleAlbumData.items.count)
    }

    func dataIndexToTableIndex(dataIndex: Int) -> Int {
        return Utilities.dataIndexToTableIndex(dataIndex: dataIndex, columns: columns, total: singleAlbumData.items.count)
    }

    func sizeForCell(dataIndex: Int) -> CGSize {
        let title   = titleString(dataIndex: dataIndex)
        let details = detailsString(dataIndex: dataIndex)
        guard let collectionView = collectionView else { return CGSize.zero }
        let maxWidth = collectionView.frame.size.width
        let width    = floor(maxWidth / CGFloat(columns))

        let titleSize   = Utilities.measureText(text: title, attributes: Utilities.textTitleAttributes(), width: width - 23)
        let detailsSize = Utilities.measureText(text: details, attributes: Utilities.textDetailsAttributes())

        return CGSize(width: width, height: ceil(titleSize.height) + ceil(detailsSize.height) + 10)
    }

    // --- Collection View ---
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let firstInRow = Int(indexPath.row / columns) * columns
        var totalSize = CGSize.zero
        for i in firstInRow..<(firstInRow+columns) {
            if i < singleAlbumData.items.count {
                let size = sizeForCell(dataIndex: tableIndexToDataIndex(tableIndex: i))
                totalSize = CGSize(width: max(size.width, totalSize.width), height: max(size.height, totalSize.height))
            }
        }
        return totalSize
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return singleAlbumData.items.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CellIdentifier, for: indexPath)
        if let cell = cell as? TTTrackCollectionViewCell {
            let dataIndex = tableIndexToDataIndex(tableIndex: indexPath.row)
            cell.trackName?.text    = titleString(dataIndex: dataIndex)
            cell.trackDetails?.text = detailsString(dataIndex: dataIndex)
            cell.trackName?.font    = Utilities.fontSized(originalSize: 17)
            cell.trackDetails?.font = Utilities.fontSized(originalSize: 15)
            cell.backgroundColor    = Utilities.cellBackgroundColor(indexPath: indexPath, currentlyPlayingTableIndex: dataIndexToTableIndex(dataIndex: currentlyPlayingDataIndex))

            // "Selected" state
            let backgroundView = UIView()
            backgroundView.backgroundColor = UIColor(red: 0.0/255.0, green:0.0/255.0, blue:0.0/255.0, alpha:15/255.0)
            cell.selectedBackgroundView = backgroundView
            return cell
        }
        return cell
    }

    // --- Segue ---
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let indexPath = self.collectionView?.indexPathsForSelectedItems?.first {
            let selectedDataIndex   = tableIndexToDataIndex(tableIndex: indexPath.row)
            let items           = singleAlbumData.items
            if items.count > 0 {
                assert(selectedDataIndex >= 0)
                assert(selectedDataIndex < items.count)
                if selectedDataIndex < items.count {
                    let songTrack       = items[selectedDataIndex]

                    var startPosition : TimeInterval = 0.0
                    if (Player.sharedInstance.nowPlayingID == songTrack.persistentID) {
                        if let time = Player.sharedInstance.getCurrentTime() {
                            startPosition = time
                        }
                    }
                    Player.sharedInstance.pause()
                    Player.sharedInstance.setQueue(items: items.map({$0.persistentID}))
                    Player.sharedInstance.setTrack(persistentID: songTrack.persistentID)
                    Player.sharedInstance.setCurrentTime(time: startPosition)
                    Player.sharedInstance.play()

                    let bookmarkTitle = Utilities.getAlbumDisplayName(album: albumTitle)
                    let bookmarkDetails = Utilities.getArtistDisplayName(artist: artistTitle)
                    Bookmarks.setCurrentPlaylist(type: EPlaylistType.Album,
                                                 persistentID: songTrack.albumPersistentID,
                                                 title: bookmarkTitle,
                                                 details: bookmarkDetails,
                                                 representativeItem: singleAlbumData.representativeItem!,
                                                 mediaItems: items)
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
        self.title = albumTitle

        // Player observer
        Player.sharedInstance.subscribe(subscriber: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if albumTitle != "" {
            self.navigationItem.title = albumTitle
        }
        else {
            self.navigationItem.title = "Album"
        }
        singleAlbumData = MusicLibrary.getSingleAlbumData(genreTitle: genreTitle, artistTitle: artistTitle, albumTitle: albumTitle)
        needsRecalculation = true
        rowToTransitionTo = -1

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
            notificationCenter.addObserver(self, selector: #selector(changedTextSize), name: NSNotification.Name.UIContentSizeCategoryDidChange, object: nil)

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
        singleAlbumData = MusicLibrary.getSingleAlbumData(genreTitle: genreTitle, artistTitle: artistTitle, albumTitle: albumTitle)
        collectionView?.reloadData()
        currentlyPlayingDataIndex = -1
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
        if let nowPlayingID = Player.sharedInstance.nowPlayingID {
            if let nowPlayingItem = MusicLibrary.getMediaItems(itemIDs: [nowPlayingID]).first {
                let newTitle = nowPlayingItem.title
                for (index, item) in singleAlbumData.items.enumerated() {
                    let testTitle = item.title
                    if testTitle == newTitle {
                        if currentlyPlayingDataIndex != index {
                            // Update table rows - update old row to remove highlight, and update new row to show highlight
                            let oldRow = dataIndexToTableIndex(dataIndex: currentlyPlayingDataIndex)
                            currentlyPlayingDataIndex = index
                            updateRows(oldRow: oldRow, newRow: dataIndexToTableIndex(dataIndex: currentlyPlayingDataIndex))
                        }
                        return
                    }
                }
            }
        }
        // No row is currently playing, so just update old row to remove highlight
        let oldRow = currentlyPlayingDataIndex
        currentlyPlayingDataIndex = -1
        updateRows(oldRow: dataIndexToTableIndex(dataIndex: oldRow), newRow: -1)
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

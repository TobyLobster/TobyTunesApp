//
//  ArtistsViewController.swift
//  TobyTunes
//
//  Created by Toby Nelson on 14/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import UIKit
import MediaPlayer

class ArtistsViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout, Subscriber {

    let CellIdentifier = "Cell"
    var genreTitle: String? = nil
    var artistsData = ArtistsData(artists: [], albumCounts: [])
    var currentlyPlayingDataIndex = -1
    var columns = 1
    var needsRecalculation = false
    var rowToTransitionTo = -1
    var registeredForNotifications = false

    func titleString(dataIndex: Int) -> String {
        let rowItem = artistsData.artists[dataIndex].representativeItem
        let artist = MusicLibrary.artistForItem(item: rowItem)
        return Utilities.getArtistDisplayName(artist: artist)
    }

    func detailsString(dataIndex: Int) -> String {
        var text : String
        let albumCount = artistsData.albumCounts[dataIndex]
        if albumCount == 1 {
            text = "1 album  •  "
        }
        else {
            text = "\(albumCount) albums  •  "
        }
        var duration = 0.0
        for item in artistsData.artists[dataIndex].items {
            duration += (item.playbackDuration as NSNumber).doubleValue
        }
        text += "\(Utilities.timeIntervalStringDHMSStyle(duration: duration))"
        return text
    }

    func tableIndexToDataIndex(tableIndex: Int) -> Int {
        return Utilities.tableIndexToDataIndex(tableIndex: tableIndex, columns: columns, total: artistsData.artists.count)
    }

    func dataIndexToTableIndex(dataIndex: Int) -> Int {
        return Utilities.dataIndexToTableIndex(dataIndex: dataIndex, columns: columns, total: artistsData.artists.count)
    }

    func sizeForCell(dataIndex: Int) -> CGSize {
        let title   = titleString(dataIndex: dataIndex)
        let details = detailsString(dataIndex: dataIndex)
        guard let collectionView = collectionView else { return CGSize.zero }
        let maxWidth = Utilities.usableWidth(of: collectionView)
        let width    = floor(maxWidth / CGFloat(columns))
        // Margin, artwork and gap on the left; room for the play button on the right. The title is
        // measured a touch narrower than it really is, so a title that only just fits still gets two lines
        let padding  = CGFloat(8+thumbnailWidth+10+8+44)

        let titleSize   = Utilities.measureText(text: title, attributes: Utilities.textTitleAttributes(), width: width - padding - 2)
        let detailsSize = Utilities.measureText(text: details, attributes: Utilities.textDetailsAttributes())

        return CGSize(width: width, height: max(CGFloat(thumbnailHeight), ceil(titleSize.height) + ceil(detailsSize.height)) + 16)
    }

    // --- Collection View ---
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let firstInRow = Int(indexPath.row / columns) * columns
        var totalSize = CGSize.zero
        for i in firstInRow..<(firstInRow+columns) {
            if i < artistsData.artists.count {
                let size = sizeForCell(dataIndex: tableIndexToDataIndex(tableIndex: i))
                totalSize = CGSize(width: max(size.width, totalSize.width), height: max(size.height, totalSize.height))
            }
        }
        return totalSize
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return artistsData.artists.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CellIdentifier, for: indexPath)
        if let cell = cell as? TTArtistsCollectionViewCell {
            let dataIndex = tableIndexToDataIndex(tableIndex: indexPath.row)
            cell.artistName?.text = titleString(dataIndex: dataIndex)
            cell.artistDetails?.text = detailsString(dataIndex: dataIndex)

            cell.artistArt?.image = UIImage(named: "logo")
            cell.artistPlay?.tag = dataIndex

            let rowItem      = artistsData.artists[dataIndex].representativeItem
            let artwork      = rowItem?.artwork
            let artworkImage = MusicLibrary.resizeArtwork(artwork: artwork, fitWithinSize: thumbnailSize)
            if artworkImage != nil {
                let artWithBorders = artworkImage!.squareThumbnail(side: thumbnailWidth)
                cell.artistArt?.image = artWithBorders
            }
            cell.artistName?.font = Utilities.rowTitleFont()
            cell.artistDetails?.font = Utilities.rowDetailsFont()
            cell.artistPlay?.titleLabel?.font = Utilities.fontSized(originalSize: 15)
            cell.backgroundColor = Utilities.cellBackgroundColor(indexPath: indexPath, currentlyPlayingTableIndex: dataIndexToTableIndex(dataIndex: currentlyPlayingDataIndex))
            cell.artistName?.textColor = Utilities.cellTitleColor(indexPath: indexPath, currentlyPlayingTableIndex: dataIndexToTableIndex(dataIndex: currentlyPlayingDataIndex))

            // "Selected" state
            cell.selectedBackgroundView = Utilities.selectedCellBackgroundView()

            return cell
        }
        return cell
    }

    // --- Segue ---
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let destViewController = segue.destination as? AlbumsViewController {
            // Go to album selection
            if let indexPath = self.collectionView?.indexPathsForSelectedItems?.first {
                let selectedDataIndex   = tableIndexToDataIndex(tableIndex: indexPath.row)

                destViewController.genreTitle  = genreTitle
                if let selectedItem = artistsData.artists[selectedDataIndex].representativeItem {
                    destViewController.artistTitle = MusicLibrary.artistForItem(item: selectedItem)
                }
            }
        }
        else {
            // Play all by artist
            guard let button = sender as? UIButton else { return }
            let selectedDataIndex = button.tag
            let selectedItem     = artistsData.artists[selectedDataIndex].representativeItem
            let artistTitle      = MusicLibrary.artistForItem(item: selectedItem)
            let singleArtistData = MusicLibrary.getSingleArtistData(genreTitle: genreTitle, artistTitle: artistTitle)
            let items            = singleArtistData.items
            if items.count > 0 {
                let songTrack       = items[0]

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

                let bookmarkTitle = Utilities.getArtistDisplayName(artist: artistTitle)
                Bookmarks.setCurrentPlaylist(type: EPlaylistType.Artist,
                                             persistentID: songTrack.artistPersistentID,
                                             title: bookmarkTitle,
                                             details: "",
                                             representativeItem: singleArtistData.representativeItem!,
                                             mediaItems: items)
            }
        }
    }

    // --- Long-press menu ---
    override func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, let indexPath = indexPaths.first else { return nil }
        let dataIndex = tableIndexToDataIndex(tableIndex: indexPath.row)
        guard dataIndex >= 0, dataIndex < artistsData.artists.count else { return nil }
        let artistTitle = MusicLibrary.artistForItem(item: artistsData.artists[dataIndex].representativeItem)
        let name = Utilities.getArtistDisplayName(artist: artistTitle)
        let genre = genreTitle
        // All the artist's songs, album by album
        let songs = { MusicLibrary.getSingleArtistData(genreTitle: genre, artistTitle: artistTitle).items }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let add = UIAction(title: "Add to Playlist…", image: UIImage(systemName: "text.badge.plus")) { _ in
                guard let self = self else { return }
                let items = songs()
                PlaylistActions.addToPlaylist(trackIDs: items.map { $0.persistentID },
                                              summary: PlaylistActions.summary(name: name, count: items.count),
                                              from: self)
            }
            return UIMenu(title: "", children: [add])
        }
    }

    // --- View ---
    override func viewDidLoad() {
        super.viewDidLoad()
        let bgColourView = UIView()
        bgColourView.backgroundColor = UIColor.systemBackground
        self.collectionView?.backgroundView = bgColourView

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Player observer, only while on screen: the player holds on to its observers, so a screen that
        // stayed subscribed would never be freed after going back
        Player.sharedInstance.unsubscribe(subscriber: self)
        Player.sharedInstance.subscribe(subscriber: self)

        if genreTitle != nil && genreTitle != "" {
            self.navigationItem.title = genreTitle
        }
        else {
            self.navigationItem.title = "Artists"
        }
        artistsData = MusicLibrary.getArtistsData(genreTitle: genreTitle)
        needsRecalculation = true
        rowToTransitionTo = -1

        registerForNotifications()
        updatePlaybackItemUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if needsRecalculation {
            recalculateColumns(size: self.view.safeAreaLayoutGuide.layoutFrame.size)
            if rowToTransitionTo >= 0 {
                let indexPath = IndexPath(row: rowToTransitionTo, section: 0)
                self.collectionView?.scrollToItem(at: indexPath, at: .bottom, animated: false)
            }
            needsRecalculation = false
            rowToTransitionTo = -1
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Player.sharedInstance.unsubscribe(subscriber: self)
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
            notificationCenter.addObserver(self, selector: #selector(changedTextSize), name: UIContentSizeCategory.didChangeNotification, object:nil)
            MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
            registeredForNotifications = true
        }
    }

    func unregisterForNotifications() {
        if registeredForNotifications {
            let notificationCenter = NotificationCenter.default
            notificationCenter.removeObserver(self, name: UIContentSizeCategory.didChangeNotification, object: nil)
            notificationCenter.removeObserver(self, name: NSNotification.Name.MPMediaLibraryDidChange, object: nil)
            MPMediaLibrary.default().endGeneratingLibraryChangeNotifications()
            registeredForNotifications = false
        }
    }

    @objc func musicLibraryUpdated() {
        artistsData = MusicLibrary.getArtistsData(genreTitle: genreTitle)
        collectionView?.reloadData()
        currentlyPlayingDataIndex = -1
        updatePlaybackItemUI()
    }

    @objc func changedTextSize() {
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
                let newArtist    = MusicLibrary.artistForItem(item: nowPlayingItem)
                for (index, artist) in artistsData.artists.enumerated() {
                    let test = MusicLibrary.artistForItem(item: artist.representativeItem)
                    if test == newArtist {
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
        columns = Utilities.recalculateColumns(size: size)
        self.collectionView?.reloadData()
    }

    // Subscriber pattern:
    var properties = ["updateTrack"]

    func notify(propertyValue: String, newValue: Double, options: [String:String]?) {
        updatePlaybackItemUI()
    }    
}

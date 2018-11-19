//
//  GenresViewController.swift
//  TobyTunes
//
//  Created by Toby Nelson on 14/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//
//  See http://code.tutsplus.com/tutorials/build-an-ios-music-player-ui-theming--pre-51297

import UIKit
import MediaPlayer

class GenresViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout, Subscriber {

    let CellIdentifier = "Cell"
    var genreData = GenreData(genres: [], artistCounts: [])
    var currentlyPlayingDataIndex = -1
    var columns = 1
    var needsRecalculation = false
    var rowToTransitionTo = -1
    var registeredForNotifications = false

    func titleString(dataIndex: Int) -> String {
        let rowItem = genreData.genres[dataIndex].representativeItem
        return Utilities.getGenreDisplayName(genre: rowItem?.genre)
    }

    func detailsString(dataIndex: Int) -> String {
        let artistCount = genreData.artistCounts[dataIndex]
        if artistCount == 1 {
            return "1 artist"
        }
        return "\(artistCount) artists"
    }

    func tableIndexToDataIndex(tableIndex: Int) -> Int {
        return Utilities.tableIndexToDataIndex(tableIndex: tableIndex, columns: columns, total: genreData.genres.count)
    }

    func dataIndexToTableIndex(dataIndex: Int) -> Int {
        return Utilities.dataIndexToTableIndex(dataIndex: dataIndex, columns: columns, total: genreData.genres.count)
    }

    func sizeForCell(dataIndex: Int) -> CGSize {
        let title   = titleString(dataIndex: dataIndex)
        let details = detailsString(dataIndex: dataIndex)
        guard let collectionView = collectionView else { return CGSize.zero }
        let maxWidth = collectionView.frame.size.width
        let width    = floor(maxWidth / CGFloat(columns))

        let detailsSize = Utilities.measureText(text: details, attributes: Utilities.textDetailsAttributes(), width: width)

        var mainTextWidth = width - detailsSize.width - (8+10+8)
        if mainTextWidth < 10 {
            mainTextWidth = 10
        }

        let titleSize = Utilities.measureText(text: title, attributes: Utilities.textTitleAttributes(), width: mainTextWidth)
        return CGSize(width: width, height: max(titleSize.height, detailsSize.height) + 18)
    }

    // --- Collection View ---
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let firstInRow = Int(indexPath.row / columns) * columns
        var totalSize = CGSize.zero
        for i in firstInRow..<(firstInRow+columns) {
            if i < genreData.genres.count {
                let size = sizeForCell(dataIndex: tableIndexToDataIndex(tableIndex: i))
                totalSize = CGSize(width: max(size.width, totalSize.width), height: max(size.height, totalSize.height))
            }
        }
        return totalSize
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return genreData.genres.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CellIdentifier, for: indexPath) as! TTGenreCollectionViewCell

        cell.textLabel!.text        = titleString(dataIndex: tableIndexToDataIndex(tableIndex: indexPath.row))
        cell.detailTextLabel?.text  = detailsString(dataIndex: tableIndexToDataIndex(tableIndex: indexPath.row))
        cell.textLabel!.font        = Utilities.fontSized(originalSize: 17)
        cell.detailTextLabel!.font  = Utilities.fontSized(originalSize: 15)
        cell.backgroundColor        = Utilities.cellBackgroundColor(indexPath: indexPath, currentlyPlayingTableIndex: dataIndexToTableIndex(dataIndex: currentlyPlayingDataIndex))

        let backgroundView = UIView()
        backgroundView.backgroundColor = UIColor(red: 0.0/255.0, green:0.0/255.0, blue:0.0/255.0, alpha:15/255.0)
        cell.selectedBackgroundView = backgroundView

        return cell
    }

    // --- Segue ---
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let destViewController = segue.destination as? ArtistsViewController {
            if let indexPath       = self.collectionView?.indexPathsForSelectedItems?.first {
                let selectedDataIndex   = tableIndexToDataIndex(tableIndex: indexPath.row)
                let selectedItem        = genreData.genres[selectedDataIndex].representativeItem
                let genreTitle          = Utilities.safeGetString(string: selectedItem!.genre)
                destViewController.genreTitle = genreTitle
            }
        }
    }

    // --- View ---
    override func viewDidLoad() {
        let bgColourView = UIView()
        bgColourView.backgroundColor = UIColor.white
        self.collectionView?.backgroundView = bgColourView

        // Player observer
        Player.sharedInstance.subscribe(subscriber: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        genreData = MusicLibrary.getGenreData()
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
            notificationCenter.addObserver(self,
                                           selector: #selector(musicLibraryUpdated),
                                           name: NSNotification.Name.MPMediaLibraryDidChange, object: nil)
            notificationCenter.addObserver(self,
                                           selector: #selector(changedTextSize),
                                           name: UIContentSizeCategory.didChangeNotification, object: nil)

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
        genreData = MusicLibrary.getGenreData()
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
                let newGenre = nowPlayingItem.genre
                for (index, genre) in genreData.genres.enumerated() {
                    let testGenre = genre.representativeItem!.genre
                    if testGenre == newGenre {
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
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        if appDelegate.isUIActive {
            updatePlaybackItemUI()
        }
    }
}

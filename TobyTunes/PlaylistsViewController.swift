//
//  PlaylistsViewController.swift
//  TobyTunes
//
//  Created by Toby Nelson on 27/09/2026.
//  Copyright © 2026 Agent Lobster. All rights reserved.
//

import UIKit
import MediaPlayer

/// What a row of the Playlists list shows, worked out once per reload.
private struct PlaylistRow {
    let playlist: UserPlaylist
    let details: String
    let artwork: UIImage?
    /// How many of the playlist's songs are in the library and can be played.
    let playableCount: Int
}

/// The Playlists tab: a single-column list of the user's playlists, working like a playlist's own
/// song list. Swipe left to delete; Edit to delete or drag to reorder; long-press for more.
class PlaylistsViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDragDelegate, UICollectionViewDropDelegate, Subscriber {

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, UUID>!
    private var rows: [UUID: PlaylistRow] = [:]
    private var playingPlaylistID: UUID? = nil
    /// Set while this screen saves a reorder itself, so it doesn't also reload on the change notification.
    private var savingOwnChange = false

    // MARK: - View

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Playlists"
        view.backgroundColor = UIColor.systemBackground

        // + for a new playlist, next to the About button; Edit on the left
        let addButton = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(newPlaylist))
        addButton.accessibilityLabel = "New Playlist"
        navigationItem.rightBarButtonItems = [addButton] + (navigationItem.rightBarButtonItems ?? [])
        navigationItem.leftBarButtonItem = editButtonItem

        configureCollectionView()

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(playlistsChanged), name: .userPlaylistsChanged, object: nil)
        notificationCenter.addObserver(self, selector: #selector(musicLibraryUpdated), name: NSNotification.Name.MPMediaLibraryDidChange, object: nil)
        notificationCenter.addObserver(self, selector: #selector(changedTextSize), name: UIContentSizeCategory.didChangeNotification, object: nil)
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()

        // Player observer
        Player.sharedInstance.subscribe(subscriber: self)

        reloadRows(animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadRows(animated: false)
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        collectionView.isEditing = editing
    }

    private func configureCollectionView() {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = UIColor.systemBackground
        // Swipe left on a playlist to delete it (after confirming)
        configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self = self, let playlistID = self.dataSource.itemIdentifier(for: indexPath) else { return nil }
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
                guard let self = self else {
                    completion(false)
                    return
                }
                PlaylistActions.confirmDelete(playlistID: playlistID, from: self)
                completion(true)
            }
            delete.image = UIImage(systemName: "trash")
            let rename = UIContextualAction(style: .normal, title: "Rename") { [weak self] _, _, completion in
                guard let self = self else {
                    completion(false)
                    return
                }
                PlaylistActions.rename(playlistID: playlistID, from: self)
                completion(true)
            }
            rename.image = UIImage(systemName: "pencil")
            return UISwipeActionsConfiguration(actions: [delete, rename])
        }

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self
        collectionView.allowsSelectionDuringEditing = false
        // Press, hold and drag a playlist to move it (as well as the handles in Edit)
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = true
        view.addSubview(collectionView)

        let cellRegistration = UICollectionView.CellRegistration<PlaylistListCell, UUID> { [weak self] cell, _, playlistID in
            self?.configure(cell: cell, playlistID: playlistID)
        }
        dataSource = UICollectionViewDiffableDataSource<Int, UUID>(collectionView: collectionView) { collectionView, indexPath, playlistID in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: playlistID)
        }

        // Drag to reorder while editing
        dataSource.reorderingHandlers.canReorderItem = { [weak self] _ in
            return self?.isEditing ?? false
        }
        dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
            guard let self = self else { return }
            // Save only: the list is still finishing the move, and must not be updated again here
            self.savingOwnChange = true
            UserPlaylists.shared.setOrder(transaction.finalSnapshot.itemIdentifiers)
            self.savingOwnChange = false
        }
    }

    // MARK: - Data

    private func reloadRows(animated: Bool) {
        let playlists = UserPlaylists.shared.playlists
        var newRows: [UUID: PlaylistRow] = [:]
        for playlist in playlists {
            let items = UserPlaylists.shared.mediaItems(for: playlist)
            var details = "No tracks"
            if !items.isEmpty {
                let duration = items.reduce(0.0) { $0 + $1.playbackDuration }
                details = (items.count == 1 ? "1 track" : "\(items.count) tracks") + "  •  " + Utilities.timeIntervalStringDHMSStyle(duration: duration)
            }
            newRows[playlist.id] = PlaylistRow(playlist: playlist,
                                               details: details,
                                               artwork: PlaylistArtwork.image(for: items, side: CGFloat(thumbnailWidth)),
                                               playableCount: items.count)
        }
        rows = newRows
        playingPlaylistID = currentPlayingPlaylistID()
        updateEmptyState()

        let ids = playlists.map { $0.id }
        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        // Playlists already showing may have changed (name, songs, artwork)
        let showing = Set(dataSource.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(ids.filter { showing.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    /// The playlist that's playing, if a playlist is what's playing.
    private func currentPlayingPlaylistID() -> UUID? {
        guard Player.sharedInstance.nowPlayingID != nil else { return nil }
        let current = Bookmarks.data.currentPlaylist
        guard current.type == .UserPlaylist else { return nil }
        return UUID(uuidString: current.userPlaylistID)
    }

    private func updateEmptyState() {
        if rows.isEmpty {
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.image = UIImage(systemName: "music.note.list")
            configuration.text = "No Playlists"
            configuration.secondaryText = "Make a playlist from songs in your library."
            var button = UIButton.Configuration.filled()
            button.title = "New Playlist"
            button.baseBackgroundColor = accentColor
            configuration.button = button
            configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in
                self?.newPlaylist()
            }
            contentUnavailableConfiguration = configuration
        }
        else {
            contentUnavailableConfiguration = nil
        }
    }

    @objc func playlistsChanged() {
        if !savingOwnChange {
            reloadRows(animated: true)
        }
    }

    @objc func musicLibraryUpdated() {
        reloadRows(animated: false)
    }

    @objc func changedTextSize() {
        reloadRows(animated: false)
    }

    // MARK: - Cells

    private func configure(cell: PlaylistListCell, playlistID: UUID) {
        guard let row = rows[playlistID] else { return }
        let isPlaying = playlistID == playingPlaylistID

        cell.nameLabel.text = row.playlist.name
        cell.nameLabel.font = Utilities.rowTitleFont()
        cell.nameLabel.textColor = isPlaying ? accentColor : UIColor.label
        cell.detailsLabel.text = row.details
        cell.detailsLabel.font = Utilities.rowDetailsFont()
        cell.setArtwork(row.artwork)

        cell.playButton.isEnabled = row.playableCount > 0
        cell.onPlay = { [weak self] in
            self?.play(playlistID: playlistID, shuffled: false)
        }
        cell.accessories = [
            .customView(configuration: cell.playAccessory),
            .delete(displayed: .whenEditing),
            .reorder(displayed: .whenEditing),
        ]

        // Highlight the playlist that's playing, like the other lists
        cell.configurationUpdateHandler = { cell, state in
            var background = UIBackgroundConfiguration.listCell().updated(for: state)
            if isPlaying && !state.isHighlighted && !state.isSelected {
                background.backgroundColor = Utilities.cellBackgroundColor(indexPath: IndexPath(row: 0, section: 0), currentlyPlayingTableIndex: 0)
            }
            cell.backgroundConfiguration = background
        }
    }

    // MARK: - Press, hold and drag to reorder

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        // In Edit the drag handles do this
        guard !isEditing, let playlistID = dataSource.itemIdentifier(for: indexPath) else { return [] }
        let dragItem = UIDragItem(itemProvider: NSItemProvider(object: playlistID.uuidString as NSString))
        dragItem.localObject = playlistID
        return [dragItem]
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        // Only playlists dragged within this list
        guard session.localDragSession != nil, collectionView.hasActiveDrag else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let dropItem = coordinator.items.first,
              let playlistID = dropItem.dragItem.localObject as? UUID else { return }
        let ids = dataSource.snapshot().itemIdentifiers
        guard let from = ids.firstIndex(of: playlistID), !ids.isEmpty else { return }

        var newIDs = ids
        newIDs.remove(at: from)
        let to = min(coordinator.destinationIndexPath?.item ?? newIDs.count, newIDs.count)
        newIDs.insert(playlistID, at: to)

        // Save, then show the new order (the list may already show it)
        savingOwnChange = true
        UserPlaylists.shared.setOrder(newIDs)
        savingOwnChange = false
        if newIDs != ids {
            var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
            snapshot.appendSections([0])
            snapshot.appendItems(newIDs)
            dataSource.apply(snapshot, animatingDifferences: true)
        }
        coordinator.drop(dropItem.dragItem, toItemAt: IndexPath(item: to, section: 0))
    }

    // MARK: - Selection and menus

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard !isEditing, let playlistID = dataSource.itemIdentifier(for: indexPath) else { return }
        open(playlistID: playlistID)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isEditing, indexPaths.count == 1, let indexPath = indexPaths.first,
              let playlistID = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            return self?.menu(for: playlistID)
        }
    }

    /// Long-press menu: Play, Shuffle, Add Songs, Rename, Delete.
    private func menu(for playlistID: UUID) -> UIMenu {
        let canPlay = (rows[playlistID]?.playableCount ?? 0) > 0
        let play = UIAction(title: "Play", image: UIImage(systemName: "play"), attributes: canPlay ? [] : .disabled) { [weak self] _ in
            self?.play(playlistID: playlistID, shuffled: false)
        }
        let shuffle = UIAction(title: "Shuffle", image: UIImage(systemName: "shuffle"), attributes: canPlay ? [] : .disabled) { [weak self] _ in
            self?.play(playlistID: playlistID, shuffled: true)
        }
        let addSongs = UIAction(title: "Add Songs", image: UIImage(systemName: "plus")) { [weak self] _ in
            guard let self = self else { return }
            PlaylistActions.addSongs(to: playlistID, from: self)
        }
        let rename = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in
            guard let self = self else { return }
            PlaylistActions.rename(playlistID: playlistID, from: self)
        }
        let delete = UIAction(title: "Delete Playlist", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            guard let self = self else { return }
            PlaylistActions.confirmDelete(playlistID: playlistID, from: self)
        }
        return UIMenu(title: "", children: [
            UIMenu(title: "", options: .displayInline, children: [play, shuffle]),
            UIMenu(title: "", options: .displayInline, children: [addSongs, rename]),
            delete,
        ])
    }

    // MARK: - Actions

    /// Plays the playlist and goes to Now Playing.
    private func play(playlistID: UUID, shuffled: Bool) {
        guard UserPlaylists.shared.play(id: playlistID, shuffled: shuffled) else { return }
        TTSegue(identifier: nil, source: self, destination: self).perform()
    }

    /// Opens a playlist's screen.
    private func open(playlistID: UUID) {
        navigationController?.pushViewController(PlaylistViewController(playlistID: playlistID), animated: true)
    }

    /// Asks for a name, then opens the new playlist and shows the song picker.
    @objc func newPlaylist() {
        if isEditing {
            setEditing(false, animated: true)
        }
        PlaylistActions.newPlaylist(from: self) { [weak self] playlistID in
            guard let self = self else { return }
            self.open(playlistID: playlistID)
            // Presented from the tab bar controller, as this screen is on its way off screen
            PlaylistActions.addSongs(to: playlistID, from: self.tabBarController ?? self)
        }
    }

    // MARK: - Subscriber (highlights the playlist that's playing)

    var properties = ["updateTrack"]

    func notify(propertyValue: String, newValue: Double, options: [String:String]?) {
        let newID = currentPlayingPlaylistID()
        guard newID != playingPlaylistID else { return }
        let changed = [playingPlaylistID, newID].compactMap { $0 }.filter { rows[$0] != nil }
        playingPlaylistID = newID
        var snapshot = dataSource.snapshot()
        let showing = Set(snapshot.itemIdentifiers)
        snapshot.reconfigureItems(changed.filter { showing.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

/// A playlist in the Playlists list: artwork, name, song count and time, and a play button on the right.
final class PlaylistListCell: UICollectionViewListCell {
    let artworkView = UIImageView()
    let nameLabel = UILabel()
    let detailsLabel = UILabel()
    let playButton = UIButton(type: .system)
    /// The play button as a row accessory (hidden while editing, to make room for the drag handle).
    private(set) var playAccessory: UICellAccessory.CustomViewConfiguration!

    /// Called when the play button is tapped.
    var onPlay: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        Utilities.styleThumbnail(artworkView)
        nameLabel.numberOfLines = 2
        nameLabel.adjustsFontForContentSizeCategory = true
        detailsLabel.textColor = UIColor.secondaryLabel
        detailsLabel.adjustsFontForContentSizeCategory = true

        Utilities.styleRowButton(playButton, systemName: "play.circle.fill", accessibilityLabel: "Play playlist")
        playButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        playAccessory = UICellAccessory.CustomViewConfiguration(customView: playButton,
                                                                placement: .trailing(displayed: .whenNotEditing),
                                                                reservedLayoutWidth: .custom(44),
                                                                maintainsFixedSize: true)

        let textArea = UILayoutGuide()
        contentView.addLayoutGuide(textArea)
        for subview in [artworkView, nameLabel, detailsLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }

        let margins = contentView.layoutMarginsGuide
        let side = CGFloat(thumbnailWidth)
        // Top and bottom limits just below required: the list first lays a row out at an estimated
        // height, and the row should give way quietly until it's measured rather than break constraints
        func belowRequired(_ constraint: NSLayoutConstraint) -> NSLayoutConstraint {
            constraint.priority = UILayoutPriority(999)
            return constraint
        }
        NSLayoutConstraint.activate([
            artworkView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            artworkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: side),
            artworkView.heightAnchor.constraint(equalToConstant: side),
            belowRequired(artworkView.topAnchor.constraint(greaterThanOrEqualTo: margins.topAnchor)),
            belowRequired(artworkView.bottomAnchor.constraint(lessThanOrEqualTo: margins.bottomAnchor)),

            textArea.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 12),
            textArea.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textArea.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            belowRequired(textArea.topAnchor.constraint(greaterThanOrEqualTo: margins.topAnchor)),
            belowRequired(textArea.bottomAnchor.constraint(lessThanOrEqualTo: margins.bottomAnchor)),

            nameLabel.topAnchor.constraint(equalTo: textArea.topAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: textArea.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: textArea.trailingAnchor),
            detailsLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            detailsLabel.leadingAnchor.constraint(equalTo: textArea.leadingAnchor),
            detailsLabel.trailingAnchor.constraint(equalTo: textArea.trailingAnchor),
            detailsLabel.bottomAnchor.constraint(equalTo: textArea.bottomAnchor),

            // Row separators line up with the text, as in other lists
            separatorLayoutGuide.leadingAnchor.constraint(equalTo: textArea.leadingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("PlaylistListCell is created in code")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onPlay = nil
    }

    /// Shows the playlist's artwork, or a placeholder when it has none.
    func setArtwork(_ image: UIImage?) {
        if let image = image {
            artworkView.image = image
            artworkView.contentMode = .scaleAspectFill
            artworkView.backgroundColor = nil
        }
        else {
            artworkView.image = UIImage(systemName: "music.note.list", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular))
            artworkView.contentMode = .center
            artworkView.backgroundColor = UIColor.secondarySystemFill
            artworkView.tintColor = UIColor.secondaryLabel
        }
    }

    @objc private func playTapped() {
        onPlay?()
    }
}

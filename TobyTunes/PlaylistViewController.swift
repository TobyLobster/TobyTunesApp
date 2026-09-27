//
//  PlaylistViewController.swift
//  TobyTunes
//
//  Created by Toby Nelson on 27/09/2026.
//  Copyright © 2026 Agent Lobster. All rights reserved.
//

import UIKit
import MediaPlayer

/// One song in a playlist. A song can be in a playlist more than once, so each entry has its own ID.
private struct SongEntry: Hashable {
    let uid = UUID()
    let trackID: UInt64

    static func == (lhs: SongEntry, rhs: SongEntry) -> Bool {
        return lhs.uid == rhs.uid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }
}

/// A playlist's screen: artwork, name, Play and Shuffle, and its songs.
/// Edit mode removes songs (also by swiping), reorders them by dragging, renames, and adds songs.
final class PlaylistViewController: UIViewController, UICollectionViewDelegate, Subscriber {

    private let playlistID: UUID
    private var playlist: UserPlaylist?
    private var entries: [SongEntry] = []
    private var itemsByID: [UInt64: MPMediaItem] = [:]
    private var thumbnails: [UInt64: UIImage] = [:]
    private var playingUID: UUID? = nil
    /// Set while this screen saves its own edits, so it doesn't reload itself on the change notification.
    private var savingOwnChanges = false
    private var isSubscribed = false
    /// The songs as they were before the last sort or tidy, so it can be undone ("Sort", say).
    /// Cleared by any other change to the playlist.
    private var undoState: (name: String, entries: [SongEntry])? = nil

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, SongEntry>!
    private weak var headerView: PlaylistHeaderView?

    private static let rowImageSize = CGSize(width: 44, height: 44)
    private static let headerArtworkSide = 160

    init(playlistID: UUID) {
        self.playlistID = playlistID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("PlaylistViewController is created in code")
    }

    // MARK: - View

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = UIColor.systemBackground

        let moreButton = UIBarButtonItem(title: nil, image: UIImage(systemName: "ellipsis.circle"), primaryAction: nil, menu: moreMenu())
        moreButton.accessibilityLabel = "More"
        let sortButton = UIBarButtonItem(title: nil, image: UIImage(systemName: "arrow.up.arrow.down"), primaryAction: nil, menu: sortMenu())
        sortButton.accessibilityLabel = "Sort"
        navigationItem.rightBarButtonItems = [editButtonItem, moreButton, sortButton]

        configureCollectionView()

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(playlistsChanged), name: .userPlaylistsChanged, object: nil)
        notificationCenter.addObserver(self, selector: #selector(musicLibraryUpdated), name: NSNotification.Name.MPMediaLibraryDidChange, object: nil)
        notificationCenter.addObserver(self, selector: #selector(changedTextSize), name: UIContentSizeCategory.didChangeNotification, object: nil)
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()

        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !isSubscribed {
            Player.sharedInstance.subscribe(subscriber: self)
            isSubscribed = true
        }
        refreshPlayingSong()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Player.sharedInstance.unsubscribe(subscriber: self)
        isSubscribed = false
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // The header can switch between stacked and side by side
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        collectionView.isEditing = editing
        updateHeader()
    }

    private func configureCollectionView() {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.headerMode = .supplementary
        configuration.backgroundColor = UIColor.systemBackground
        // Swipe left on a song to remove it
        configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self = self, let entry = self.dataSource.itemIdentifier(for: indexPath) else { return nil }
            let remove = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, completion in
                self?.remove(entry: entry)
                completion(true)
            }
            remove.image = UIImage(systemName: "trash")
            return UISwipeActionsConfiguration(actions: [remove])
        }

        // Plain lists pin section headers to the top while scrolling; this header (artwork, name, Play and
        // Shuffle) should scroll away with the songs instead
        let listConfiguration = configuration
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            let section = NSCollectionLayoutSection.list(using: listConfiguration, layoutEnvironment: layoutEnvironment)
            for supplementaryItem in section.boundarySupplementaryItems {
                supplementaryItem.pinToVisibleBounds = false
            }
            return section
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self
        collectionView.allowsSelectionDuringEditing = false
        view.addSubview(collectionView)

        let cellRegistration = UICollectionView.CellRegistration<PlaylistSongCell, SongEntry> { [weak self] cell, _, entry in
            self?.configure(cell: cell, entry: entry)
        }
        dataSource = UICollectionViewDiffableDataSource<Int, SongEntry>(collectionView: collectionView) { collectionView, indexPath, entry in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: entry)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<PlaylistHeaderView>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] header, _, _ in
            guard let self = self else { return }
            self.headerView = header
            header.onPlay = { [weak self] in self?.playAll(shuffled: false) }
            header.onShuffle = { [weak self] in self?.playAll(shuffled: true) }
            header.onAddSongs = { [weak self] in self?.addSongs() }
            header.onRename = { [weak self] in self?.rename() }
            self.configureHeader(header)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }

        // Drag to reorder while editing
        dataSource.reorderingHandlers.canReorderItem = { [weak self] _ in
            return self?.isEditing ?? false
        }
        dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
            guard let self = self else { return }
            self.entries = transaction.finalSnapshot.itemIdentifiers
            self.undoState = nil
            let trackIDs = self.entries.map { $0.trackID }
            self.save { UserPlaylists.shared.setTracks(trackIDs, for: self.playlistID) }
            // The list is still finishing the move here, and applying another change now is not
            // allowed (it crashes), so update the playing highlight just afterwards
            DispatchQueue.main.async { [weak self] in
                self?.refreshPlayingSong()
            }
        }
    }

    // MARK: - Data

    /// Reads the playlist again (after it's changed elsewhere, or the library has changed).
    private func reload() {
        guard let playlist = UserPlaylists.shared.playlist(id: playlistID) else {
            // Deleted: leave this screen
            navigationController?.popViewController(animated: true)
            return
        }
        self.playlist = playlist
        navigationItem.title = playlist.name
        undoState = nil

        let found = MusicLibrary.getMediaItems(itemIDs: Array(Set(playlist.trackIDs)))
        itemsByID = Dictionary(found.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })
        thumbnails = [:]
        entries = playlist.trackIDs.map { SongEntry(trackID: $0) }
        playingUID = playingEntry()?.uid

        var snapshot = NSDiffableDataSourceSnapshot<Int, SongEntry>()
        snapshot.appendSections([0])
        snapshot.appendItems(entries)
        dataSource.apply(snapshot, animatingDifferences: false)
        updateHeader()
    }

    /// Saves one of this screen's own edits to the store.
    private func save(_ change: () -> Void) {
        savingOwnChanges = true
        change()
        savingOwnChanges = false
        playlist = UserPlaylists.shared.playlist(id: playlistID)
    }

    private func isPlayable(_ entry: SongEntry) -> Bool {
        return itemsByID[entry.trackID] != nil
    }

    /// The song that's playing, if this playlist is what's playing.
    private func playingEntry() -> SongEntry? {
        guard let nowPlayingID = Player.sharedInstance.nowPlayingID else { return nil }
        let context = Bookmarks.data.currentPlaylist
        guard context.type == .UserPlaylist, context.userPlaylistID == playlistID.uuidString else { return nil }

        // The player knows the song's place in the playlist's normal order (counting only playable
        // songs), which picks the right copy of a song that's in the playlist twice
        let player = Player.sharedInstance
        if let queueIndex = player.indexNowPlaying {
            let sourceIndex = player.queue.tracks[queueIndex].sourceIndex
            let playable = entries.filter { isPlayable($0) }
            if sourceIndex >= 0 && sourceIndex < playable.count && playable[sourceIndex].trackID == nowPlayingID {
                return playable[sourceIndex]
            }
        }
        return entries.first { $0.trackID == nowPlayingID }
    }

    private func refreshPlayingSong() {
        let newUID = playingEntry()?.uid
        guard newUID != playingUID else { return }
        let changed = entries.filter { $0.uid == newUID || $0.uid == playingUID }
        playingUID = newUID
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(changed)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    @objc func playlistsChanged() {
        if !savingOwnChanges {
            reload()
        }
    }

    @objc func musicLibraryUpdated() {
        reload()
    }

    @objc func changedTextSize() {
        reload()
    }

    // MARK: - Cells

    private func configure(cell: PlaylistSongCell, entry: SongEntry) {
        let isPlaying = entry.uid == playingUID

        if let item = itemsByID[entry.trackID] {
            cell.titleLabel.text = Utilities.getTrackDisplayName(track: item.title)
            cell.titleLabel.textColor = isPlaying ? accentColor : UIColor.label
            cell.durationLabel.text = Utilities.timeIntervalStringClockStyle(duration: item.playbackDuration)
            cell.subtitleLabel.text = Utilities.getArtistDisplayName(artist: item.artist) + "  •  " + Utilities.getAlbumDisplayName(album: item.albumTitle)
            cell.setArtwork(thumbnail(for: item))
        }
        else {
            cell.titleLabel.text = "Song Not Available"
            cell.titleLabel.textColor = UIColor.tertiaryLabel
            cell.durationLabel.text = nil
            cell.subtitleLabel.text = "It's no longer in the library on this device"
            cell.setArtwork(nil)
        }
        cell.titleLabel.font = Utilities.rowTitleFont()
        cell.subtitleLabel.font = Utilities.rowDetailsFont()
        cell.durationLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .regular))

        cell.accessories = [.delete(displayed: .whenEditing), .reorder(displayed: .whenEditing)]

        // Highlight the song that's playing, like the other lists
        cell.configurationUpdateHandler = { cell, state in
            var background = UIBackgroundConfiguration.listCell().updated(for: state)
            if isPlaying && !state.isHighlighted && !state.isSelected {
                background.backgroundColor = Utilities.cellBackgroundColor(indexPath: IndexPath(row: 0, section: 0), currentlyPlayingTableIndex: 0)
            }
            cell.backgroundConfiguration = background
        }
    }

    private func thumbnail(for item: MPMediaItem) -> UIImage? {
        if let image = thumbnails[item.persistentID] {
            return image
        }
        let size = PlaylistViewController.rowImageSize
        guard let image = MusicLibrary.resizeArtwork(artwork: item.artwork, fitWithinSize: size)?.squareThumbnail(side: Int(size.width)) else { return nil }
        thumbnails[item.persistentID] = image
        return image
    }

    // MARK: - Header

    @discardableResult
    private func configureHeader(_ header: PlaylistHeaderView) -> Bool {
        guard let playlist = playlist else { return false }
        let playable = entries.compactMap { itemsByID[$0.trackID] }
        var details = "No tracks"
        if !playable.isEmpty {
            let duration = playable.reduce(0.0) { $0 + $1.playbackDuration }
            details = (playable.count == 1 ? "1 track" : "\(playable.count) tracks") + "  •  " + Utilities.timeIntervalStringDHMSStyle(duration: duration)
        }
        let side = PlaylistViewController.headerArtworkSide
        let artwork = PlaylistArtwork.image(for: playable, side: CGFloat(side))

        let mode: PlaylistHeaderView.Mode = isEditing ? .editing : (playable.isEmpty ? .empty : .normal)
        return header.configure(name: playlist.name, details: details, artwork: artwork, mode: mode)
    }

    private func updateHeader() {
        guard let header = headerView else { return }
        // Only a new name can change the header's height: re-measure it then, but not while a song
        // is being removed or moved (that would disturb the list's animation)
        if configureHeader(header) {
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    // MARK: - Actions

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard !isEditing,
              let entry = dataSource.itemIdentifier(for: indexPath),
              isPlayable(entry),
              let position = entries.firstIndex(of: entry) else { return }
        // Its place among the songs that can be played
        let playableIndex = entries[..<position].filter { isPlayable($0) }.count
        if UserPlaylists.shared.play(id: playlistID, from: playableIndex) {
            TTSegue(identifier: nil, source: self, destination: self).perform()
        }
    }

    private func playAll(shuffled: Bool) {
        if UserPlaylists.shared.play(id: playlistID, shuffled: shuffled) {
            TTSegue(identifier: nil, source: self, destination: self).perform()
        }
    }

    private func remove(entry: SongEntry) {
        guard let position = entries.firstIndex(of: entry) else { return }
        undoState = nil
        entries.remove(at: position)
        save { UserPlaylists.shared.removeTracks(at: IndexSet(integer: position), from: playlistID) }

        var snapshot = dataSource.snapshot()
        snapshot.deleteItems([entry])
        dataSource.apply(snapshot, animatingDifferences: true)
        updateHeader()
    }

    private func addSongs() {
        PlaylistActions.addSongs(to: playlistID, from: self)
    }

    private func rename() {
        PlaylistActions.rename(playlistID: playlistID, from: self)
    }

    private func moreMenu() -> UIMenu {
        let addSongs = UIAction(title: "Add Songs", image: UIImage(systemName: "plus")) { [weak self] _ in
            self?.addSongs()
        }
        let rename = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in
            self?.rename()
        }
        let delete = UIAction(title: "Delete Playlist", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            guard let self = self else { return }
            PlaylistActions.confirmDelete(playlistID: self.playlistID, from: self)
        }
        return UIMenu(title: "", children: [
            UIMenu(title: "", options: .displayInline, children: [addSongs, rename]),
            delete,
        ])
    }

    // MARK: - Sorting and tidying

    private func sortMenu() -> UIMenu {
        let sort = UIAction(title: "Sort by Genre, Artist, Album, Track", image: UIImage(systemName: "arrow.up.arrow.down")) { [weak self] _ in
            self?.sortSongs()
        }
        let removeDuplicates = UIAction(title: "Remove Duplicates", image: UIImage(systemName: "square.on.square.dashed")) { [weak self] _ in
            self?.removeDuplicates()
        }
        // Only offered when some songs are no longer on this device
        let removeUnavailable = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self = self, self.entries.contains(where: { !self.isPlayable($0) }) else {
                completion([])
                return
            }
            completion([UIAction(title: "Remove Unavailable Songs", image: UIImage(systemName: "exclamationmark.circle"), attributes: .destructive) { [weak self] _ in
                self?.removeUnavailable()
            }])
        }
        // "Undo Sort" (etc.) after a sort or tidy, until the playlist is changed some other way
        let undo = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self = self, let undoState = self.undoState else {
                completion([])
                return
            }
            completion([UIMenu(title: "", options: .displayInline, children: [
                UIAction(title: "Undo \(undoState.name)", image: UIImage(systemName: "arrow.uturn.backward")) { [weak self] _ in
                    self?.undoTidy()
                },
            ])])
        }
        return UIMenu(title: "", children: [undo, sort, removeDuplicates, removeUnavailable])
    }

    /// Applies a sort or tidy, remembering the songs as they were so it can be undone, and says what
    /// happened in a message with an Undo button.
    private func tidy(to newEntries: [SongEntry], name: String, message: String) {
        let previous = entries
        applyNewOrder(newEntries)
        undoState = (name, previous)
        if let window = view.window {
            PlaylistActions.showToast(message, in: window, actionTitle: "Undo") { [weak self] in
                self?.undoTidy()
            }
        }
    }

    /// Puts the songs back as they were before the last sort or tidy.
    private func undoTidy() {
        guard let undoState = undoState else { return }
        self.undoState = nil
        applyNewOrder(undoState.entries)
    }

    /// Removes the songs that are no longer in the library on this device.
    private func removeUnavailable() {
        let kept = entries.filter { isPlayable($0) }
        let removedCount = entries.count - kept.count
        guard removedCount > 0 else { return }
        tidy(to: kept, name: "Remove Unavailable Songs",
             message: removedCount == 1 ? "Removed 1 unavailable song" : "Removed \(removedCount) unavailable songs")
    }

    /// Sorts the songs by genre, then artist, then album, then track number, and saves the new order
    /// (drag songs in Edit to fine-tune it after). Songs that aren't available stay at the end.
    private func sortSongs() {
        guard entries.count > 1 else { return }
        // Ties keep their current order
        let playable = entries.enumerated().filter { isPlayable($0.element) }
        let unavailable = entries.filter { !isPlayable($0) }
        let sorted = playable.sorted { a, b in
            guard let itemA = itemsByID[a.element.trackID], let itemB = itemsByID[b.element.trackID] else { return a.offset < b.offset }
            return PlaylistViewController.isOrderedBefore(itemA, itemB) ?? (a.offset < b.offset)
        }.map { $0.element } + unavailable
        guard sorted != entries else {
            if let window = view.window {
                PlaylistActions.showToast("Already in order", in: window)
            }
            return
        }
        tidy(to: sorted, name: "Sort", message: "Sorted by genre, artist, album and track")
    }

    /// Genre, then artist (album artist, as in the Artists list), then album, then disc and track number.
    /// Returns nil when the two songs are equal on all of these.
    private static func isOrderedBefore(_ a: MPMediaItem, _ b: MPMediaItem) -> Bool? {
        func compare<T: Comparable>(_ x: T, _ y: T) -> ComparisonResult {
            return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        }
        let order: [ComparisonResult] = [
            (a.genre ?? "").localizedStandardCompare(b.genre ?? ""),
            MusicLibrary.artistForItem(item: a).localizedStandardCompare(MusicLibrary.artistForItem(item: b)),
            (a.albumTitle ?? "").localizedStandardCompare(b.albumTitle ?? ""),
            compare(a.discNumber, b.discNumber),
            compare(a.albumTrackNumber, b.albumTrackNumber),
        ]
        for result in order where result != .orderedSame {
            return result == .orderedAscending
        }
        return nil
    }

    /// Removes second and later copies of any song, keeping each song where it first appears.
    private func removeDuplicates() {
        var seen = Set<UInt64>()
        let kept = entries.filter { seen.insert($0.trackID).inserted }
        let removedCount = entries.count - kept.count
        guard removedCount > 0 else {
            if let window = view.window {
                PlaylistActions.showToast("No duplicates found", in: window)
            }
            return
        }
        tidy(to: kept, name: "Remove Duplicates",
             message: removedCount == 1 ? "Removed 1 duplicate" : "Removed \(removedCount) duplicates")
    }

    /// Saves a new list of songs (reordered or with some removed) and animates the change.
    private func applyNewOrder(_ newEntries: [SongEntry]) {
        entries = newEntries
        let trackIDs = entries.map { $0.trackID }
        save { UserPlaylists.shared.setTracks(trackIDs, for: playlistID) }

        var snapshot = NSDiffableDataSourceSnapshot<Int, SongEntry>()
        snapshot.appendSections([0])
        snapshot.appendItems(entries)
        dataSource.apply(snapshot, animatingDifferences: true) { [weak self] in
            self?.refreshPlayingSong()
        }
        updateHeader()
    }

    // MARK: - Subscriber (highlights the song that's playing)

    var properties = ["updateTrack"]

    func notify(propertyValue: String, newValue: Double, options: [String:String]?) {
        refreshPlayingSong()
    }
}

/// A song in a playlist: artwork, then the title with the length on the right of the same line,
/// and the artist and album underneath across the full width.
final class PlaylistSongCell: UICollectionViewListCell {
    let artworkView = UIImageView()
    let titleLabel = UILabel()
    let durationLabel = UILabel()
    let subtitleLabel = UILabel()

    private static let artworkSide: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)

        artworkView.contentMode = .scaleAspectFill
        artworkView.layer.cornerRadius = 6
        artworkView.layer.cornerCurve = .continuous
        artworkView.clipsToBounds = true

        titleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = UIColor.secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true
        durationLabel.textColor = UIColor.secondaryLabel
        durationLabel.textAlignment = .right
        durationLabel.adjustsFontForContentSizeCategory = true
        // The length always shows in full; the title is shortened instead
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textArea = UILayoutGuide()
        contentView.addLayoutGuide(textArea)
        for subview in [artworkView, titleLabel, durationLabel, subtitleLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }

        let margins = contentView.layoutMarginsGuide
        let side = PlaylistSongCell.artworkSide
        // Top and bottom limits just below required: the list first lays a row out at an estimated
        // height (59pt, 1pt short of 44pt artwork plus margins), and then the row should give way
        // quietly until it's measured, rather than breaking constraints
        let artworkTop = artworkView.topAnchor.constraint(greaterThanOrEqualTo: margins.topAnchor)
        artworkTop.priority = UILayoutPriority(999)
        let artworkBottom = artworkView.bottomAnchor.constraint(lessThanOrEqualTo: margins.bottomAnchor)
        artworkBottom.priority = UILayoutPriority(999)
        let textTop = textArea.topAnchor.constraint(greaterThanOrEqualTo: margins.topAnchor)
        textTop.priority = UILayoutPriority(999)
        let textBottom = textArea.bottomAnchor.constraint(lessThanOrEqualTo: margins.bottomAnchor)
        textBottom.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            artworkView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            artworkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: side),
            artworkView.heightAnchor.constraint(equalToConstant: side),
            artworkTop,
            artworkBottom,

            textArea.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 12),
            textArea.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textArea.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textTop,
            textBottom,

            // Top line: title, with the length on the right
            titleLabel.topAnchor.constraint(equalTo: textArea.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: textArea.leadingAnchor),
            durationLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            durationLabel.trailingAnchor.constraint(equalTo: textArea.trailingAnchor),
            durationLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),

            // Second line: artist and album, across the full width
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: textArea.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: textArea.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: textArea.bottomAnchor),

            // Row separators line up with the text, as in other lists
            separatorLayoutGuide.leadingAnchor.constraint(equalTo: textArea.leadingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("PlaylistSongCell is created in code")
    }

    /// Shows the song's artwork, or a music note when it has none.
    func setArtwork(_ image: UIImage?) {
        if let image = image {
            artworkView.image = image
            artworkView.contentMode = .scaleAspectFill
            artworkView.backgroundColor = nil
        }
        else {
            artworkView.image = UIImage(systemName: "music.note")
            artworkView.contentMode = .center
            artworkView.backgroundColor = UIColor.secondarySystemFill
            artworkView.tintColor = UIColor.secondaryLabel
        }
    }
}

/// The top of a playlist's screen: artwork, name, details, and two buttons.
/// The buttons are Play and Shuffle; Add Songs when the playlist is empty; Rename and Add Songs while editing.
final class PlaylistHeaderView: UICollectionReusableView {
    enum Mode {
        case normal, empty, editing
    }

    var onPlay: (() -> Void)?
    var onShuffle: (() -> Void)?
    var onAddSongs: (() -> Void)?
    var onRename: (() -> Void)?

    private let artworkView = UIImageView()
    private let nameLabel = UILabel()
    private let detailsLabel = UILabel()
    private let leftButton = UIButton(type: .system)
    private let rightButton = UIButton(type: .system)
    private var mode: Mode = .normal
    /// Artwork and the rest (name, details, buttons): stacked in a narrow layout, side by side in a wide one.
    private let outerStack = UIStackView()
    private let infoStack = UIStackView()
    private var infoFullWidth: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)

        artworkView.contentMode = .scaleAspectFill
        artworkView.layer.cornerRadius = 12
        artworkView.layer.cornerCurve = .continuous
        artworkView.clipsToBounds = true

        let nameFont = UIFont.systemFont(ofSize: 22, weight: .bold)
        nameLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: nameFont)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 0

        detailsLabel.font = Utilities.rowDetailsFont()
        detailsLabel.textColor = UIColor.secondaryLabel
        detailsLabel.textAlignment = .center

        leftButton.addAction(UIAction { [weak self] _ in self?.leftTapped() }, for: .touchUpInside)
        rightButton.addAction(UIAction { [weak self] _ in self?.rightTapped() }, for: .touchUpInside)

        let buttonRow = UIStackView(arrangedSubviews: [leftButton, rightButton])
        buttonRow.axis = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 12

        for view in [nameLabel, detailsLabel, buttonRow] {
            infoStack.addArrangedSubview(view)
        }
        infoStack.axis = .vertical
        infoStack.spacing = 4
        infoStack.setCustomSpacing(16, after: detailsLabel)

        outerStack.addArrangedSubview(artworkView)
        outerStack.addArrangedSubview(infoStack)
        outerStack.alignment = .center
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outerStack)

        let side = CGFloat(160)
        let rowWidth = buttonRow.widthAnchor.constraint(equalTo: infoStack.widthAnchor)
        rowWidth.priority = .defaultHigh
        // The name and buttons are as wide as they can be: the full width when stacked, and whatever's
        // left beside the artwork when side by side. Just below required, so it never clashes with the
        // stack's own spacing while it's switching between the two (the stack updates a moment later)
        infoFullWidth = infoStack.widthAnchor.constraint(equalTo: outerStack.widthAnchor)
        infoFullWidth.priority = UILayoutPriority(999)
        // Just below required, so the header gives way while the list is animating it to a new size
        // (the collection view briefly holds it at its old height) instead of breaking constraints
        let bottom = outerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        bottom.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            bottom,
            outerStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: side),
            artworkView.heightAnchor.constraint(equalToConstant: side),
            rowWidth,
            infoFullWidth,
            buttonRow.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            buttonRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        applyLayout()
        registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]) { (header: PlaylistHeaderView, _: UITraitCollection) in
            header.applyLayout()
        }
    }

    /// Side by side (artwork on the left) on iPad and on a phone in landscape, where there's width to
    /// spare and little height; stacked and centred otherwise.
    private func applyLayout() {
        let wide = traitCollection.horizontalSizeClass == .regular || traitCollection.verticalSizeClass == .compact
        outerStack.axis = wide ? .horizontal : .vertical
        outerStack.spacing = wide ? 20 : 14
        infoStack.alignment = wide ? .leading : .center
        nameLabel.textAlignment = wide ? .natural : .center
        detailsLabel.textAlignment = wide ? .natural : .center
    }

    required init?(coder: NSCoder) {
        fatalError("PlaylistHeaderView is created in code")
    }

    /// Returns true if the header may need a new height (the name has changed).
    @discardableResult
    func configure(name: String, details: String, artwork: UIImage?, mode: Mode) -> Bool {
        let nameChanged = nameLabel.text != name
        nameLabel.text = name
        detailsLabel.text = details
        if let artwork = artwork {
            artworkView.image = artwork
            artworkView.contentMode = .scaleAspectFill
            artworkView.backgroundColor = nil
        }
        else {
            artworkView.image = UIImage(systemName: "music.note.list", withConfiguration: UIImage.SymbolConfiguration(pointSize: 56, weight: .regular))
            artworkView.contentMode = .center
            artworkView.backgroundColor = UIColor.secondarySystemFill
            artworkView.tintColor = UIColor.secondaryLabel
        }

        self.mode = mode
        switch mode {
        case .normal:
            style(leftButton, title: "Play", symbol: "play.fill")
            style(rightButton, title: "Shuffle", symbol: "shuffle")
            rightButton.isHidden = false
        case .empty:
            style(leftButton, title: "Add Songs", symbol: "plus")
            rightButton.isHidden = true
        case .editing:
            style(leftButton, title: "Rename", symbol: "pencil")
            style(rightButton, title: "Add Songs", symbol: "plus")
            rightButton.isHidden = false
        }
        return nameChanged
    }

    private func style(_ button: UIButton, title: String, symbol: String) {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 6
        configuration.cornerStyle = .large
        configuration.baseForegroundColor = accentColor
        configuration.baseBackgroundColor = accentColor
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: UIFont.systemFont(ofSize: 17, weight: .semibold))
            return attributes
        }
        button.configuration = configuration
    }

    private func leftTapped() {
        switch mode {
        case .normal:  onPlay?()
        case .empty:   onAddSongs?()
        case .editing: onRename?()
        }
    }

    private func rightTapped() {
        switch mode {
        case .normal:  onShuffle?()
        case .empty:   break
        case .editing: onAddSongs?()
        }
    }
}

// MARK: - Playlist artwork

/// A playlist's artwork: a 2×2 grid of the first four different album covers, just the first cover
/// when there are fewer than four, or nil when none of its songs have artwork.
enum PlaylistArtwork {
    static func image(for items: [MPMediaItem], side: CGFloat) -> UIImage? {
        let size = CGSize(width: side, height: side)
        var artworks: [MPMediaItemArtwork] = []
        var seenAlbums = Set<UInt64>()
        for item in items {
            guard let artwork = item.artwork, artwork.image(at: size) != nil else { continue }
            // One cover per album
            if item.albumPersistentID != 0 && !seenAlbums.insert(item.albumPersistentID).inserted { continue }
            artworks.append(artwork)
            if artworks.count == 4 { break }
        }
        guard let first = artworks.first else { return nil }
        if artworks.count < 4 {
            return MusicLibrary.resizeArtwork(artwork: first, fitWithinSize: size)?.squareThumbnail(side: Int(side))
        }

        let half = side / 2
        let tileSize = CGSize(width: half, height: half)
        return UIGraphicsImageRenderer(size: size).image { _ in
            for (index, artwork) in artworks.enumerated() {
                let origin = CGPoint(x: CGFloat(index % 2) * half, y: CGFloat(index / 2) * half)
                // Drawn a little larger than the tile, then clipped to it, so each cover fills its square
                if let cover = MusicLibrary.resizeArtwork(artwork: artwork, fitWithinSize: size)?.squareThumbnail(side: Int(side)) {
                    cover.draw(in: CGRect(origin: origin, size: tileSize))
                }
            }
        }
    }
}

// MARK: - Shared playlist actions

/// Playlist actions used by both the Playlists list and a playlist's own screen.
enum PlaylistActions {

    /// Asks for a name, makes the playlist, then calls `created` with its ID.
    static func newPlaylist(from presenter: UIViewController, created: @escaping (UUID) -> Void) {
        let alert = UIAlertController(title: "New Playlist", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Playlist Name"
            field.autocapitalizationType = .words
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        let create = UIAlertAction(title: "Create", style: .default) { [weak alert] _ in
            let playlist = UserPlaylists.shared.create(name: alert?.textFields?.first?.text ?? "")
            created(playlist.id)
        }
        alert.addAction(create)
        alert.preferredAction = create
        presenter.present(alert, animated: true, completion: nil)
    }

    static func rename(playlistID: UUID, from presenter: UIViewController) {
        guard let playlist = UserPlaylists.shared.playlist(id: playlistID) else { return }
        let alert = UIAlertController(title: "Rename Playlist", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = playlist.name
            field.placeholder = "Playlist Name"
            field.autocapitalizationType = .words
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        let save = UIAlertAction(title: "Save", style: .default) { [weak alert] _ in
            UserPlaylists.shared.rename(id: playlistID, to: alert?.textFields?.first?.text ?? "")
        }
        alert.addAction(save)
        alert.preferredAction = save
        presenter.present(alert, animated: true, completion: nil)
    }

    static func confirmDelete(playlistID: UUID, from presenter: UIViewController) {
        guard let playlist = UserPlaylists.shared.playlist(id: playlistID) else { return }
        let alert = UIAlertController(title: "Delete “\(playlist.name)”?",
                                      message: Bookmarks.hasBookmark(forUserPlaylistID: playlistID)
                                        ? "The songs stay in your library. Its bookmark will also be removed."
                                        : "The songs stay in your library.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            UserPlaylists.shared.delete(id: playlistID)
        })
        presenter.present(alert, animated: true, completion: nil)
    }

    static func addSongs(to playlistID: UUID, from presenter: UIViewController) {
        PlaylistSongPicker.present(for: playlistID, from: presenter)
    }
}

/// Shows Apple's song picker and adds the chosen songs to the end of a playlist.
final class PlaylistSongPicker: NSObject, MPMediaPickerControllerDelegate {
    /// The picker only keeps a weak reference to its delegate, so the open one is kept here.
    private static var active: PlaylistSongPicker?
    private let playlistID: UUID

    private init(playlistID: UUID) {
        self.playlistID = playlistID
        super.init()
    }

    static func present(for playlistID: UUID, from presenter: UIViewController) {
        guard let playlist = UserPlaylists.shared.playlist(id: playlistID) else { return }
        let handler = PlaylistSongPicker(playlistID: playlistID)
        active = handler

        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = true
        // Only songs TobyTunes can play: downloaded, and not copy-protected
        picker.showsCloudItems = false
        picker.showsItemsWithProtectedAssets = false
        picker.prompt = "Add songs to “\(playlist.name)”"
        picker.delegate = handler
        presenter.present(picker, animated: true, completion: nil)
    }

    func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
        UserPlaylists.shared.addTracks(mediaItemCollection.items.map { $0.persistentID }, to: playlistID)
        mediaPicker.dismiss(animated: true, completion: nil)
        PlaylistSongPicker.active = nil
    }

    func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
        mediaPicker.dismiss(animated: true, completion: nil)
        PlaylistSongPicker.active = nil
    }
}

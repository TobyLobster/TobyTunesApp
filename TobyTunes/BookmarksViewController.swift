//
//  BookmarksViewController.swift
//  TobyTunes
//
//  Created by Toby Nelson on 14/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import UIKit
import MediaPlayer

/// The Bookmarks tab, with two lists switched at the top: Bookmarks (places you've chosen to keep) and
/// Recent (History: the last albums, artists and playlists played, each remembering its place). Both
/// work like the Playlists list: tap to resume, swipe left to remove, press and hold for more. Bookmarks
/// can also be reordered (Edit, or press, hold and drag); Recent can be cleared.
class BookmarksViewController: UICollectionViewController, UICollectionViewDragDelegate, UICollectionViewDropDelegate, Subscriber {

    private enum Mode: Int {
        case bookmarks = 0, recent = 1
    }

    private var mode: Mode = .bookmarks
    private let modeControl = UISegmentedControl(items: ["Bookmarks", "Recent"])
    private lazy var clearButton = UIBarButtonItem(title: "Clear", style: .plain, target: self, action: #selector(confirmClearHistory))

    private var dataSource: UICollectionViewDiffableDataSource<Int, Int>!
    /// Artwork by bookmark or History entry ID, cleared on reload.
    private var thumbnails: [Int: UIImage] = [:]

    // MARK: - View

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Bookmarks"
        // The Bookmarks | Recent switch takes the title's place
        modeControl.selectedSegmentIndex = mode.rawValue
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        navigationItem.titleView = modeControl
        navigationItem.largeTitleDisplayMode = .never
        updateLeftButton()

        configureList()

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(musicLibraryUpdated), name: NSNotification.Name.MPMediaLibraryDidChange, object: nil)
        notificationCenter.addObserver(self, selector: #selector(changedTextSize), name: UIContentSizeCategory.didChangeNotification, object: nil)
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()

        // Player observer
        Player.sharedInstance.subscribe(subscriber: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Bookmarks and History change while this screen is hidden
        reload(animated: false)
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        collectionView.isEditing = editing
    }

    @objc private func modeChanged() {
        mode = Mode(rawValue: modeControl.selectedSegmentIndex) ?? .bookmarks
        if isEditing {
            setEditing(false, animated: false)
        }
        updateLeftButton()
        reload(animated: false, fresh: true)
    }

    /// Edit for Bookmarks; Clear for Recent.
    private func updateLeftButton() {
        navigationItem.leftBarButtonItem = mode == .bookmarks ? editButtonItem : clearButton
        clearButton.isEnabled = !Bookmarks.history.isEmpty
    }

    private func configureList() {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = UIColor.systemBackground
        // Swipe left: delete a bookmark; remove a Recent entry (or keep it as a bookmark)
        configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self = self, let id = self.dataSource.itemIdentifier(for: indexPath) else { return nil }
            let delete = UIContextualAction(style: .destructive, title: self.mode == .bookmarks ? "Delete" : "Remove") { [weak self] _, _, completion in
                self?.remove(id: id)
                completion(true)
            }
            delete.image = UIImage(systemName: "trash")
            var actions = [delete]
            if self.mode == .recent && !Bookmarks.isBookmarked(historyEntryId: id) {
                let bookmark = UIContextualAction(style: .normal, title: "Bookmark") { [weak self] _, _, completion in
                    self?.bookmark(historyEntryId: id)
                    completion(true)
                }
                bookmark.image = UIImage(systemName: "bookmark")
                bookmark.backgroundColor = accentColor
                actions.append(bookmark)
            }
            return UISwipeActionsConfiguration(actions: actions)
        }
        collectionView.collectionViewLayout = UICollectionViewCompositionalLayout.list(using: configuration)
        collectionView.allowsSelectionDuringEditing = false
        // The list's reordering is done by the Edit handles and by dragging, not this older gesture
        installsStandardGestureForInteractiveMovement = false
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = true

        let cellRegistration = UICollectionView.CellRegistration<BookmarkListCell, Int> { [weak self] cell, _, id in
            self?.configure(cell: cell, id: id)
        }
        dataSource = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) { collectionView, indexPath, id in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: id)
        }

        // Drag the handles to reorder bookmarks while editing (Recent stays newest first)
        dataSource.reorderingHandlers.canReorderItem = { [weak self] _ in
            guard let self = self else { return false }
            return self.isEditing && self.mode == .bookmarks
        }
        dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
            // Save only: the list is still finishing the move, and must not be updated again here
            guard self?.mode == .bookmarks else { return }
            Bookmarks.setOrder(transaction.finalSnapshot.itemIdentifiers)
        }
    }

    // MARK: - Data

    /// The places shown in the current list.
    private var marks: [Bookmark] {
        return mode == .bookmarks ? Bookmarks.data.marks : Bookmarks.history
    }

    private func mark(id: Int) -> Bookmark? {
        return mode == .bookmarks ? Bookmarks.findMarkWithId(bookmarkId: id) : Bookmarks.findHistoryEntry(id: id)
    }

    /// Shows the current list again. `fresh` replaces it outright (after switching lists).
    private func reload(animated: Bool, fresh: Bool = false) {
        thumbnails = [:]
        let ids = marks.map { $0.id }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        if !fresh {
            // Places already showing will have moved on (progress, playing highlight)
            let showing = Set(dataSource.snapshot().itemIdentifiers)
            snapshot.reconfigureItems(ids.filter { showing.contains($0) })
        }
        if fresh {
            dataSource.applySnapshotUsingReloadData(snapshot)
        }
        else {
            dataSource.apply(snapshot, animatingDifferences: animated)
        }
        updateEmptyState()
        updateLeftButton()
    }

    private func updateEmptyState() {
        guard marks.isEmpty else {
            contentUnavailableConfiguration = nil
            return
        }
        var configuration = UIContentUnavailableConfiguration.empty()
        if mode == .bookmarks {
            configuration.image = UIImage(systemName: "bookmark")
            configuration.text = "No Bookmarks"
            configuration.secondaryText = "Tap the bookmark button on Now Playing to remember your place in an album, artist or playlist."
        }
        else {
            configuration.image = UIImage(systemName: "clock.arrow.circlepath")
            configuration.text = "Nothing Played Yet"
            configuration.secondaryText = "The albums, artists and playlists you play appear here, so you can pick up where you left off."
        }
        contentUnavailableConfiguration = configuration
    }

    @objc func musicLibraryUpdated() {
        reload(animated: false)
    }

    @objc func changedTextSize() {
        reload(animated: false)
    }

    // MARK: - Cells

    private func configure(cell: BookmarkListCell, id: Int) {
        guard let mark = self.mark(id: id) else { return }
        let followingID = mode == .bookmarks ? Bookmarks.currentBookmarkId : Bookmarks.currentHistoryId
        let isPlaying = Player.sharedInstance.nowPlayingID != nil && id == followingID

        let total = mark.playlist.totalDuration
        let elapsed = total > 0 ? mark.elapsedTime() : 0
        // What it is (e.g. the artist, for an album), then how much is left
        var details: [String] = []
        if !mark.playlist.details.isEmpty {
            details.append(mark.playlist.details)
        }
        if total > 0 {
            details.append(Utilities.timeIntervalStringDHMSStyle(duration: max(0, total - elapsed)) + " left")
        }

        cell.nameLabel.text = mark.playlist.title
        cell.nameLabel.font = Utilities.rowTitleFont()
        cell.nameLabel.textColor = isPlaying ? accentColor : UIColor.label
        cell.detailsLabel.text = details.joined(separator: "  •  ")
        cell.detailsLabel.font = Utilities.rowDetailsFont()
        cell.progress = total > 0 ? CGFloat(elapsed / total) : 0
        cell.setArtwork(thumbnail(for: mark))

        cell.onOptions = { [weak self, weak cell] in
            self?.showOptions(for: id, from: cell?.optionsButton)
        }
        cell.accessories = [
            .customView(configuration: cell.optionsAccessory),
            .delete(displayed: .whenEditing),
            .reorder(displayed: .whenEditing),
        ]

        // Highlight the one for what's playing, like the other lists
        cell.configurationUpdateHandler = { cell, state in
            var background = UIBackgroundConfiguration.listCell().updated(for: state)
            if isPlaying && !state.isHighlighted && !state.isSelected {
                background.backgroundColor = Utilities.cellBackgroundColor(indexPath: IndexPath(row: 0, section: 0), currentlyPlayingTableIndex: 0)
            }
            cell.backgroundConfiguration = background
        }
    }

    private func thumbnail(for mark: Bookmark) -> UIImage? {
        if let image = thumbnails[mark.id] {
            return image
        }
        guard let item = MusicLibrary.getMediaItems(itemIDs: [mark.playlist.representativeItemID]).first,
              let image = MusicLibrary.resizeArtwork(artwork: item.artwork, fitWithinSize: thumbnailSize)?.squareThumbnail(side: thumbnailWidth) else { return nil }
        thumbnails[mark.id] = image
        return image
    }

    // MARK: - Actions

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard !isEditing, let id = dataSource.itemIdentifier(for: indexPath) else { return }
        resume(id: id, fromStart: false)
    }

    /// Plays the bookmark or Recent entry (from where it was left, or from the start) and goes to Now Playing.
    private func resume(id: Int, fromStart: Bool) {
        let started: Bool
        if mode == .bookmarks {
            if fromStart {
                Bookmarks.resetBookmark(bookmarkId: id)
            }
            started = Bookmarks.resumeBookmark(bookmarkId: id)
        }
        else {
            started = Bookmarks.resumeHistoryEntry(id: id, fromStart: fromStart)
        }
        if started {
            TTSegue(identifier: nil, source: self, destination: self).perform()
        }
        else if let window = view.window {
            PlaylistActions.showToast("None of its songs are on this device", in: window)
        }
    }

    /// Deletes a bookmark, or removes an entry from Recent.
    private func remove(id: Int) {
        if mode == .bookmarks {
            guard Bookmarks.removeBookmark(bookmarkId: id) != nil else { return }
        }
        else {
            Bookmarks.removeHistoryEntry(id: id)
        }
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems([id])
        dataSource.apply(snapshot, animatingDifferences: true)
        updateEmptyState()
        updateLeftButton()
    }

    /// Keeps a Recent entry as a bookmark too.
    private func bookmark(historyEntryId id: Int) {
        let added = Bookmarks.bookmarkHistoryEntry(id: id)
        if let window = view.window {
            PlaylistActions.showToast(added ? "Bookmarked" : "Already bookmarked", in: window)
        }
    }

    @objc private func confirmClearHistory() {
        let sheet = UIAlertController(title: "Clear Recent?", message: "Your bookmarks aren't affected.", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Clear Recent", style: .destructive) { [weak self] _ in
            Bookmarks.clearHistory()
            self?.reload(animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        sheet.popoverPresentationController?.barButtonItem = clearButton
        present(sheet, animated: true, completion: nil)
    }

    /// The choices for a bookmark or Recent entry, for its long-press menu and its ⋯ button.
    private func menuActions(for id: Int) -> (play: [UIAction], other: [UIAction]) {
        let resume = UIAction(title: "Resume", image: UIImage(systemName: "play")) { [weak self] _ in
            self?.resume(id: id, fromStart: false)
        }
        let restart = UIAction(title: "Play From Start", image: UIImage(systemName: "backward.end")) { [weak self] _ in
            self?.resume(id: id, fromStart: true)
        }
        if mode == .bookmarks {
            let delete = UIAction(title: "Delete Bookmark", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.remove(id: id)
            }
            return ([resume, restart], [delete])
        }
        let alreadyBookmarked = Bookmarks.isBookmarked(historyEntryId: id)
        let bookmark = UIAction(title: alreadyBookmarked ? "Bookmarked" : "Bookmark",
                                image: UIImage(systemName: alreadyBookmarked ? "bookmark.fill" : "bookmark"),
                                attributes: alreadyBookmarked ? .disabled : []) { [weak self] _ in
            self?.bookmark(historyEntryId: id)
        }
        let remove = UIAction(title: "Remove from Recent", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.remove(id: id)
        }
        return ([resume, restart], [bookmark, remove])
    }

    /// The ⋯ button: the same choices as the long-press menu.
    private func showOptions(for id: Int, from sourceView: UIView?) {
        guard let mark = self.mark(id: id) else { return }
        let sheet = UIAlertController(title: mark.playlist.title, message: mark.playlist.details.isEmpty ? nil : mark.playlist.details, preferredStyle: .actionSheet)
        let actions = menuActions(for: id)
        for action in actions.play + actions.other {
            let style: UIAlertAction.Style = action.attributes.contains(.destructive) ? .destructive : .default
            let alertAction = UIAlertAction(title: action.title, style: style) { _ in
                action.performWithSender(nil, target: nil)
            }
            alertAction.isEnabled = !action.attributes.contains(.disabled)
            sheet.addAction(alertAction)
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        // iPad shows it as a popover from the button
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView ?? view
            popover.sourceRect = (sourceView ?? view).bounds
        }
        present(sheet, animated: true, completion: nil)
    }

    override func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isEditing, indexPaths.count == 1, let indexPath = indexPaths.first,
              let id = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }
            let actions = self.menuActions(for: id)
            var children: [UIMenuElement] = [UIMenu(title: "", options: .displayInline, children: actions.play)]
            children.append(contentsOf: actions.other as [UIMenuElement])
            return UIMenu(title: "", children: children)
        }
    }

    // MARK: - Press, hold and drag to reorder (Bookmarks only)

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        // In Edit the drag handles do this; Recent stays newest first
        guard !isEditing, mode == .bookmarks, let id = dataSource.itemIdentifier(for: indexPath) else { return [] }
        let dragItem = UIDragItem(itemProvider: NSItemProvider(object: String(id) as NSString))
        dragItem.localObject = id
        return [dragItem]
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        // Only bookmarks dragged within this list
        guard mode == .bookmarks, session.localDragSession != nil, collectionView.hasActiveDrag else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard mode == .bookmarks,
              let dropItem = coordinator.items.first,
              let id = dropItem.dragItem.localObject as? Int else { return }
        let ids = dataSource.snapshot().itemIdentifiers
        guard let from = ids.firstIndex(of: id) else { return }

        var newIDs = ids
        newIDs.remove(at: from)
        let to = min(coordinator.destinationIndexPath?.item ?? newIDs.count, newIDs.count)
        newIDs.insert(id, at: to)

        // Save, then show the new order (the list may already show it)
        Bookmarks.setOrder(newIDs)
        if newIDs != ids {
            var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
            snapshot.appendSections([0])
            snapshot.appendItems(newIDs)
            dataSource.apply(snapshot, animatingDifferences: true)
        }
        coordinator.drop(dropItem.dragItem, toItemAt: IndexPath(item: to, section: 0))
    }

    // MARK: - Subscriber (keeps the playing one's highlight and progress up to date)

    var properties = ["updateTrack"]

    func notify(propertyValue: String, newValue: Double, options: [String:String]?) {
        guard dataSource != nil else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

/// A bookmark in the Bookmarks list: artwork, name, details and time left, a progress bar, and a ⋯
/// button on the right for its options.
final class BookmarkListCell: UICollectionViewListCell {
    let artworkView = UIImageView()
    let nameLabel = UILabel()
    let detailsLabel = UILabel()
    let optionsButton = UIButton(type: .system)
    private let progressTrack = UIView()
    private let progressFill = UIView()
    /// The ⋯ button as a row accessory (hidden while editing, to make room for the drag handle).
    private(set) var optionsAccessory: UICellAccessory.CustomViewConfiguration!

    /// Called when the ⋯ button is tapped.
    var onOptions: (() -> Void)?

    /// How far through the bookmark playback is, 0...1.
    var progress: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        Utilities.styleThumbnail(artworkView)
        nameLabel.numberOfLines = 2
        nameLabel.adjustsFontForContentSizeCategory = true
        detailsLabel.textColor = UIColor.secondaryLabel
        detailsLabel.adjustsFontForContentSizeCategory = true
        progressTrack.backgroundColor = UIColor.tertiarySystemFill
        progressTrack.layer.cornerRadius = 2
        progressTrack.clipsToBounds = true
        progressFill.backgroundColor = accentColor
        progressFill.layer.cornerRadius = 2
        progressTrack.addSubview(progressFill)

        Utilities.styleRowButton(optionsButton, systemName: "ellipsis.circle.fill", accessibilityLabel: "Bookmark options")
        optionsButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        optionsButton.addTarget(self, action: #selector(optionsTapped), for: .touchUpInside)
        optionsAccessory = UICellAccessory.CustomViewConfiguration(customView: optionsButton,
                                                                   placement: .trailing(displayed: .whenNotEditing),
                                                                   reservedLayoutWidth: .custom(44),
                                                                   maintainsFixedSize: true)

        let textArea = UILayoutGuide()
        contentView.addLayoutGuide(textArea)
        for subview in [artworkView, nameLabel, detailsLabel, progressTrack] {
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

            // Name, details and progress bar, centred together beside the artwork
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
            progressTrack.topAnchor.constraint(equalTo: detailsLabel.bottomAnchor, constant: 6),
            progressTrack.leadingAnchor.constraint(equalTo: textArea.leadingAnchor),
            progressTrack.trailingAnchor.constraint(equalTo: textArea.trailingAnchor),
            progressTrack.heightAnchor.constraint(equalToConstant: 4),
            progressTrack.bottomAnchor.constraint(equalTo: textArea.bottomAnchor),

            // Row separators line up with the text, as in other lists
            separatorLayoutGuide.leadingAnchor.constraint(equalTo: textArea.leadingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("BookmarkListCell is created in code")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let fraction = min(1, max(0, progress))
        progressFill.frame = CGRect(x: 0, y: 0, width: progressTrack.bounds.width * fraction, height: progressTrack.bounds.height)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onOptions = nil
    }

    /// Shows the artwork, or a bookmark icon when there's none.
    func setArtwork(_ image: UIImage?) {
        if let image = image {
            artworkView.image = image
            artworkView.contentMode = .scaleAspectFill
            artworkView.backgroundColor = nil
        }
        else {
            artworkView.image = UIImage(systemName: "bookmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular))
            artworkView.contentMode = .center
            artworkView.backgroundColor = UIColor.secondarySystemFill
            artworkView.tintColor = UIColor.secondaryLabel
        }
    }

    @objc private func optionsTapped() {
        onOptions?()
    }
}

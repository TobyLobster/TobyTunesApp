//
//  BookmarksViewController.swift
//  TobyTunes
//
//  Created by Toby Nelson on 14/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import UIKit
import MediaPlayer

/// The Bookmarks tab: a single-column list of bookmarks, each remembering a place in an album, artist
/// or playlist. Works like the Playlists list: tap to resume, swipe left to delete, Edit to delete or
/// drag to reorder, press and hold for more (or to drag).
class BookmarksViewController: UICollectionViewController, UICollectionViewDragDelegate, UICollectionViewDropDelegate, Subscriber {

    private var dataSource: UICollectionViewDiffableDataSource<Int, Int>!
    /// Artwork by bookmark ID, cleared on reload.
    private var thumbnails: [Int: UIImage] = [:]

    // MARK: - View

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Bookmarks"
        navigationItem.leftBarButtonItem = editButtonItem

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
        // Bookmarks are added and moved on while this screen is hidden
        reload(animated: false)
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        collectionView.isEditing = editing
    }

    private func configureList() {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = UIColor.systemBackground
        // Swipe left on a bookmark to delete it
        configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self = self, let bookmarkId = self.dataSource.itemIdentifier(for: indexPath) else { return nil }
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
                self?.delete(bookmarkId: bookmarkId)
                completion(true)
            }
            delete.image = UIImage(systemName: "trash")
            return UISwipeActionsConfiguration(actions: [delete])
        }
        collectionView.collectionViewLayout = UICollectionViewCompositionalLayout.list(using: configuration)
        collectionView.allowsSelectionDuringEditing = false
        // The list's reordering is done by the Edit handles and by dragging, not this older gesture
        installsStandardGestureForInteractiveMovement = false
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = true

        let cellRegistration = UICollectionView.CellRegistration<BookmarkListCell, Int> { [weak self] cell, _, bookmarkId in
            self?.configure(cell: cell, bookmarkId: bookmarkId)
        }
        dataSource = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) { collectionView, indexPath, bookmarkId in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: bookmarkId)
        }

        // Drag the handles to reorder while editing
        dataSource.reorderingHandlers.canReorderItem = { [weak self] _ in
            return self?.isEditing ?? false
        }
        dataSource.reorderingHandlers.didReorder = { transaction in
            // Save only: the list is still finishing the move, and must not be updated again here
            Bookmarks.setOrder(transaction.finalSnapshot.itemIdentifiers)
        }
    }

    // MARK: - Data

    private func reload(animated: Bool) {
        thumbnails = [:]
        let ids = (0..<Bookmarks.count()).compactMap { Bookmarks.getBookmarkAtIndex(index: $0)?.id }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        // Bookmarks already showing will have moved on (progress, playing highlight)
        let showing = Set(dataSource.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(ids.filter { showing.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: animated)
        updateEmptyState()
    }

    private func updateEmptyState() {
        if Bookmarks.count() == 0 {
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.image = UIImage(systemName: "bookmark")
            configuration.text = "No Bookmarks"
            configuration.secondaryText = "Tap the bookmark button on Now Playing to remember your place in an album, artist or playlist."
            contentUnavailableConfiguration = configuration
        }
        else {
            contentUnavailableConfiguration = nil
        }
    }

    @objc func musicLibraryUpdated() {
        reload(animated: false)
    }

    @objc func changedTextSize() {
        reload(animated: false)
    }

    // MARK: - Cells

    private func configure(cell: BookmarkListCell, bookmarkId: Int) {
        guard let mark = Bookmarks.findMarkWithId(bookmarkId: bookmarkId) else { return }
        let isPlaying = Player.sharedInstance.nowPlayingID != nil && bookmarkId == Bookmarks.currentBookmarkId

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
            self?.showOptions(for: bookmarkId, from: cell?.optionsButton)
        }
        cell.accessories = [
            .customView(configuration: cell.optionsAccessory),
            .delete(displayed: .whenEditing),
            .reorder(displayed: .whenEditing),
        ]

        // Highlight the bookmark for what's playing, like the other lists
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
        guard !isEditing, let bookmarkId = dataSource.itemIdentifier(for: indexPath) else { return }
        resume(bookmarkId: bookmarkId, fromStart: false)
    }

    /// Plays the bookmark (from where it was left, or from the start) and goes to Now Playing.
    private func resume(bookmarkId: Int, fromStart: Bool) {
        if fromStart {
            Bookmarks.resetBookmark(bookmarkId: bookmarkId)
        }
        if Bookmarks.resumeBookmark(bookmarkId: bookmarkId) {
            TTSegue(identifier: nil, source: self, destination: self).perform()
        }
        else if let window = view.window {
            PlaylistActions.showToast("None of its songs are on this device", in: window)
        }
    }

    private func delete(bookmarkId: Int) {
        guard Bookmarks.removeBookmark(bookmarkId: bookmarkId) != nil else { return }
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems([bookmarkId])
        dataSource.apply(snapshot, animatingDifferences: true)
        updateEmptyState()
    }

    private func actions(for bookmarkId: Int) -> [UIAction] {
        return [
            UIAction(title: "Resume", image: UIImage(systemName: "play")) { [weak self] _ in
                self?.resume(bookmarkId: bookmarkId, fromStart: false)
            },
            UIAction(title: "Play From Start", image: UIImage(systemName: "backward.end")) { [weak self] _ in
                self?.resume(bookmarkId: bookmarkId, fromStart: true)
            },
            UIAction(title: "Delete Bookmark", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.delete(bookmarkId: bookmarkId)
            },
        ]
    }

    /// The ⋯ button on a bookmark: the same choices as its long-press menu.
    private func showOptions(for bookmarkId: Int, from sourceView: UIView?) {
        guard let mark = Bookmarks.findMarkWithId(bookmarkId: bookmarkId) else { return }
        let sheet = UIAlertController(title: mark.playlist.title, message: mark.playlist.details.isEmpty ? nil : mark.playlist.details, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Resume", style: .default) { [weak self] _ in
            self?.resume(bookmarkId: bookmarkId, fromStart: false)
        })
        sheet.addAction(UIAlertAction(title: "Play From Start", style: .default) { [weak self] _ in
            self?.resume(bookmarkId: bookmarkId, fromStart: true)
        })
        sheet.addAction(UIAlertAction(title: "Delete Bookmark", style: .destructive) { [weak self] _ in
            self?.delete(bookmarkId: bookmarkId)
        })
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
              let bookmarkId = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }
            let actions = self.actions(for: bookmarkId)
            return UIMenu(title: "", children: [
                UIMenu(title: "", options: .displayInline, children: Array(actions.prefix(2))),
                actions[2],
            ])
        }
    }

    // MARK: - Press, hold and drag to reorder

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        // In Edit the drag handles do this
        guard !isEditing, let bookmarkId = dataSource.itemIdentifier(for: indexPath) else { return [] }
        let dragItem = UIDragItem(itemProvider: NSItemProvider(object: String(bookmarkId) as NSString))
        dragItem.localObject = bookmarkId
        return [dragItem]
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        // Only bookmarks dragged within this list
        guard session.localDragSession != nil, collectionView.hasActiveDrag else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let dropItem = coordinator.items.first,
              let bookmarkId = dropItem.dragItem.localObject as? Int else { return }
        let ids = dataSource.snapshot().itemIdentifiers
        guard let from = ids.firstIndex(of: bookmarkId) else { return }

        var newIDs = ids
        newIDs.remove(at: from)
        let to = min(coordinator.destinationIndexPath?.item ?? newIDs.count, newIDs.count)
        newIDs.insert(bookmarkId, at: to)

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

    // MARK: - Subscriber (keeps the playing bookmark's highlight and progress up to date)

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

//
//  AddToPlaylistViewController.swift
//  TobyTunes
//
//  Created by Toby Nelson on 27/09/2026.
//  Copyright © 2026 Agent Lobster. All rights reserved.
//

import UIKit
import MediaPlayer

/// "Add to Playlist": a sheet listing the playlists (and New Playlist…) to add some songs to.
final class AddToPlaylistViewController: UITableViewController {

    private let trackIDs: [UInt64]
    private let summary: String
    private var playlists: [UserPlaylist] = []
    private var thumbnails: [UUID: UIImage] = [:]
    private var playableCounts: [UUID: Int] = [:]
    private let cellIdentifier = "Cell"
    private static let imageSize = CGSize(width: 44, height: 44)

    /// `summary` describes what's being added, e.g. “Abbey Road” • 17 songs.
    init(trackIDs: [UInt64], summary: String) {
        self.trackIDs = trackIDs
        self.summary = summary
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("AddToPlaylistViewController is created in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Add to Playlist"
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true, completion: nil)
        })
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellIdentifier)

        playlists = UserPlaylists.shared.playlists
        for playlist in playlists {
            let items = UserPlaylists.shared.mediaItems(for: playlist)
            playableCounts[playlist.id] = items.count
            thumbnails[playlist.id] = PlaylistArtwork.image(for: items, side: AddToPlaylistViewController.imageSize.width)
        }
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 1 : playlists.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? summary : (playlists.isEmpty ? nil : "Playlists")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.imageProperties.maximumSize = AddToPlaylistViewController.imageSize
        content.imageProperties.reservedLayoutSize = AddToPlaylistViewController.imageSize
        content.imageProperties.cornerRadius = 6
        content.textProperties.font = Utilities.rowTitleFont() ?? UIFont.preferredFont(forTextStyle: .body)
        content.secondaryTextProperties.font = Utilities.rowDetailsFont() ?? UIFont.preferredFont(forTextStyle: .subheadline)
        content.secondaryTextProperties.color = UIColor.secondaryLabel

        if indexPath.section == 0 {
            content.text = "New Playlist…"
            content.textProperties.color = accentColor
            content.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
            content.imageProperties.tintColor = accentColor
        }
        else {
            let playlist = playlists[indexPath.row]
            let count = playableCounts[playlist.id] ?? 0
            content.text = playlist.name
            content.secondaryText = count == 1 ? "1 track" : (count == 0 ? "No tracks" : "\(count) tracks")
            if let thumbnail = thumbnails[playlist.id] {
                content.image = thumbnail
            }
            else {
                content.image = UIImage(systemName: "music.note.list")
                content.imageProperties.tintColor = UIColor.secondaryLabel
            }
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            // Make a playlist with these songs in it
            PlaylistActions.newPlaylist(from: self) { [weak self] playlistID in
                guard let self = self, let playlist = UserPlaylists.shared.playlist(id: playlistID) else { return }
                self.finish(adding: self.trackIDs, to: playlist)
            }
        }
        else {
            choose(playlist: playlists[indexPath.row])
        }
    }

    // MARK: - Adding

    /// Adds the songs, first checking whether any are already in the playlist.
    private func choose(playlist: UserPlaylist) {
        let existing = Set(playlist.trackIDs)
        let newIDs = trackIDs.filter { !existing.contains($0) }
        if newIDs.count == trackIDs.count {
            finish(adding: trackIDs, to: playlist)
            return
        }

        let alreadyCount = trackIDs.count - newIDs.count
        let title: String
        let message: String
        if trackIDs.count == 1 {
            title = "Already in Playlist"
            message = "This song is already in “\(playlist.name)”."
        }
        else if newIDs.isEmpty {
            title = "Already in Playlist"
            message = "These songs are already in “\(playlist.name)”."
        }
        else {
            title = "Some Songs Already in Playlist"
            message = alreadyCount == 1
                ? "1 of these songs is already in “\(playlist.name)”."
                : "\(alreadyCount) of these songs are already in “\(playlist.name)”."
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if !newIDs.isEmpty {
            let skip = UIAlertAction(title: "Skip Them", style: .default) { [weak self] _ in
                self?.finish(adding: newIDs, to: playlist)
            }
            alert.addAction(skip)
            alert.preferredAction = skip
        }
        alert.addAction(UIAlertAction(title: "Add Anyway", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.finish(adding: self.trackIDs, to: playlist)
        })
        alert.addAction(UIAlertAction(title: newIDs.isEmpty ? "Don't Add" : "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func finish(adding ids: [UInt64], to playlist: UserPlaylist) {
        UserPlaylists.shared.addTracks(ids, to: playlist.id)
        let message = ids.count == 1 ? "Added to “\(playlist.name)”" : "Added \(ids.count) songs to “\(playlist.name)”"
        let window = view.window
        dismiss(animated: true) {
            if let window = window {
                PlaylistActions.showToast(message, in: window)
            }
        }
    }
}

extension PlaylistActions {

    /// Shows the "Add to Playlist" sheet for some songs. `summary` describes them, e.g. “Abbey Road” • 17 songs.
    static func addToPlaylist(trackIDs: [UInt64], summary: String, from presenter: UIViewController) {
        guard !trackIDs.isEmpty else { return }
        let chooser = AddToPlaylistViewController(trackIDs: trackIDs, summary: summary)
        let navigationController = UINavigationController(rootViewController: chooser)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        // From the tab bar controller, so the sheet follows the phone's light/dark setting even when
        // opened from the always-dark Now Playing screen
        (presenter.tabBarController ?? presenter).present(navigationController, animated: true, completion: nil)
    }

    /// A summary for the sheet's heading: the name in quotes, and the number of songs if more than one.
    static func summary(name: String, count: Int) -> String {
        return count == 1 ? "“\(name)”" : "“\(name)”  •  \(count) songs"
    }

    /// The toast showing now, so a new one replaces it.
    private static weak var currentToast: UIView?

    /// A short message that appears near the bottom of the screen and fades away. With an action
    /// (e.g. Undo) it shows a button too, and stays a little longer.
    static func showToast(_ message: String, in window: UIWindow, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        currentToast?.removeFromSuperview()

        let label = UILabel()
        label.text = message
        label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: UIFont.systemFont(ofSize: 15, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor.label
        label.textAlignment = .center
        label.numberOfLines = 2

        let row = UIStackView(arrangedSubviews: [label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        blur.layer.cornerRadius = 20
        blur.layer.cornerCurve = .continuous
        blur.clipsToBounds = true
        blur.isUserInteractionEnabled = action != nil

        if let actionTitle = actionTitle, let action = action {
            label.textAlignment = .natural
            var configuration = UIButton.Configuration.plain()
            configuration.title = actionTitle
            configuration.baseForegroundColor = accentColor
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: UIFont.systemFont(ofSize: 15, weight: .bold))
                return attributes
            }
            let button = UIButton(configuration: configuration)
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.addAction(UIAction { [weak blur] _ in
                action()
                UIView.animate(withDuration: 0.2, animations: {
                    blur?.alpha = 0
                }, completion: { _ in
                    blur?.removeFromSuperview()
                })
            }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }

        blur.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(row)
        window.addSubview(blur)
        currentToast = blur

        let vertical: CGFloat = action == nil ? 11 : 6
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: vertical),
            row.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -vertical),
            row.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: action == nil ? -18 : -10),
            blur.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            blur.widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, constant: -48),
            // Above the tab bar
            blur.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -84),
        ])

        blur.alpha = 0
        blur.transform = CGAffineTransform(translationX: 0, y: 12)
        UIView.animate(withDuration: 0.25) {
            blur.alpha = 1
            blur.transform = .identity
        }
        // Fade out later (timed separately, so the button stays tappable until then)
        let showFor: TimeInterval = action == nil ? 2.0 : 4.5
        DispatchQueue.main.asyncAfter(deadline: .now() + showFor) { [weak blur] in
            guard let blur = blur, blur.superview != nil else { return }
            UIView.animate(withDuration: 0.3, animations: {
                blur.alpha = 0
            }, completion: { _ in
                blur.removeFromSuperview()
            })
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

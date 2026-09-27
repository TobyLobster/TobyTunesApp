//
//  UserPlaylists.swift
//  TobyTunes
//
//  Created by Toby Nelson on 27/09/2026.
//  Copyright © 2026 Agent Lobster. All rights reserved.
//

import Foundation
import MediaPlayer

/// A playlist the user has made in TobyTunes.
struct UserPlaylist: Codable, Equatable {
    var id: UUID
    var name: String
    /// The playlist's songs in order. A song can appear more than once.
    var trackIDs: [UInt64]
    var created: Date
    var modified: Date

    init(name: String, trackIDs: [UInt64] = []) {
        self.id = UUID()
        self.name = name
        self.trackIDs = trackIDs
        self.created = Date()
        self.modified = self.created
    }

    enum CodingKeys: String, CodingKey {
        case id, name, trackIDs, created, modified
    }

    // Song IDs are saved as text: they're 64-bit numbers, which some JSON readers can't hold exactly.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        trackIDs = try container.decode([String].self, forKey: .trackIDs).compactMap { UInt64($0) }
        created = try container.decode(Date.self, forKey: .created)
        modified = try container.decode(Date.self, forKey: .modified)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(trackIDs.map { String($0) }, forKey: .trackIDs)
        try container.encode(created, forKey: .created)
        try container.encode(modified, forKey: .modified)
    }
}

extension Notification.Name {
    /// Posted on the main thread whenever a playlist is created, changed or deleted.
    static let userPlaylistsChanged = Notification.Name("TTUserPlaylistsChanged")
}

/// The user's playlists, saved in the app's data folder. Use from the main thread.
final class UserPlaylists {
    static let shared = UserPlaylists()

    /// Newest first.
    private(set) var playlists: [UserPlaylist] = []

    private init() {
        load()
    }

    // MARK: - Reading

    func playlist(id: UUID) -> UserPlaylist? {
        return playlists.first { $0.id == id }
    }

    func index(of id: UUID) -> Int? {
        return playlists.firstIndex { $0.id == id }
    }

    /// The playlist's songs that are in the library, in order. Songs no longer in the library are skipped.
    func mediaItems(for playlist: UserPlaylist) -> [MPMediaItem] {
        return MusicLibrary.getMediaItems(itemIDs: playlist.trackIDs)
    }

    /// A name to use when the user leaves the name empty.
    static let defaultName = "Untitled Playlist"

    static func cleanedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultName : trimmed
    }

    // MARK: - Changing

    @discardableResult
    func create(name: String, trackIDs: [UInt64] = []) -> UserPlaylist {
        let playlist = UserPlaylist(name: UserPlaylists.cleanedName(name), trackIDs: trackIDs)
        playlists.insert(playlist, at: 0)
        changed()
        return playlist
    }

    func rename(id: UUID, to name: String) {
        let newName = UserPlaylists.cleanedName(name)
        update(id: id) { $0.name = newName }
        Bookmarks.userPlaylistRenamed(id: id, name: newName)
    }

    /// Puts the playlists in a new order (after the user rearranges them). IDs not given keep their
    /// place at the end.
    func setOrder(_ ids: [UUID]) {
        var reordered = ids.compactMap { id in playlists.first { $0.id == id } }
        reordered += playlists.filter { playlist in !ids.contains(playlist.id) }
        guard reordered.map({ $0.id }) != playlists.map({ $0.id }) else { return }
        playlists = reordered
        changed()
    }

    func delete(id: UUID) {
        guard let index = self.index(of: id) else { return }
        playlists.remove(at: index)
        // Its bookmark goes too
        Bookmarks.userPlaylistDeleted(id: id)
        changed()
    }

    /// Adds songs to the end of a playlist.
    func addTracks(_ trackIDs: [UInt64], to id: UUID) {
        guard !trackIDs.isEmpty else { return }
        update(id: id) { $0.trackIDs.append(contentsOf: trackIDs) }
    }

    /// Removes songs by their positions in the playlist.
    func removeTracks(at offsets: IndexSet, from id: UUID) {
        update(id: id) { playlist in
            for offset in offsets.sorted(by: >) where offset < playlist.trackIDs.count {
                playlist.trackIDs.remove(at: offset)
            }
        }
    }

    /// Moves the song at `source` so it ends up at position `destination`.
    func moveTrack(from source: Int, to destination: Int, in id: UUID) {
        update(id: id) { playlist in
            guard source >= 0, source < playlist.trackIDs.count,
                  destination >= 0, destination < playlist.trackIDs.count else { return }
            let track = playlist.trackIDs.remove(at: source)
            playlist.trackIDs.insert(track, at: destination)
        }
    }

    /// Replaces all of a playlist's songs, e.g. after editing.
    func setTracks(_ trackIDs: [UInt64], for id: UUID) {
        update(id: id) { $0.trackIDs = trackIDs }
    }

    private func update(id: UUID, _ change: (inout UserPlaylist) -> Void) {
        guard let index = self.index(of: id) else { return }
        change(&playlists[index])
        playlists[index].modified = Date()
        changed()
    }

    private func changed() {
        save()
        NotificationCenter.default.post(name: .userPlaylistsChanged, object: self)
    }

    // MARK: - Playing

    /// Plays a playlist, starting from a song or shuffled. `index` is a position among the playlist's songs
    /// that are in the library (as returned by mediaItems(for:)). Returns false if there's nothing to play.
    @discardableResult
    func play(id: UUID, from index: Int = 0, shuffled: Bool = false) -> Bool {
        guard let playlist = self.playlist(id: id) else { return false }
        let items = mediaItems(for: playlist)
        guard !items.isEmpty else { return false }

        let player = Player.sharedInstance
        let startIndex = shuffled ? 0 : min(max(index, 0), items.count - 1)

        // Tapping the song that's already playing carries on from where it is
        var startPosition: TimeInterval = 0.0
        if !shuffled, player.nowPlayingID == items[startIndex].persistentID, let time = player.getCurrentTime() {
            startPosition = time
        }

        player.pause()
        player.setQueue(items: items.map { $0.persistentID })
        if shuffled {
            player.setShuffle(true)
        }
        player.setTrack(index: startIndex)
        player.setCurrentTime(time: startPosition)
        player.play()

        Bookmarks.setCurrentPlaylist(type: .UserPlaylist,
                                     persistentID: 0,
                                     title: playlist.name,
                                     details: "Playlist",
                                     representativeItem: items[0],
                                     mediaItems: items,
                                     userPlaylistID: playlist.id.uuidString)
        return true
    }

    // MARK: - Storage

    private var storageURL: URL? {
        return Utilities.applicationDataDirectory()?.appendingPathComponent("playlists.json", isDirectory: false)
    }

    private func save() {
        guard let url = storageURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(playlists).write(to: url, options: .atomic)
        } catch {
            print("Failed to save playlists: \(error)")
        }
    }

    private func load() {
        guard let url = storageURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            playlists = try decoder.decode([UserPlaylist].self, from: Data(contentsOf: url))
        } catch {
            print("Failed to load playlists: \(error)")
        }
    }
}

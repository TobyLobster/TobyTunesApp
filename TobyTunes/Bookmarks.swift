//
//  Bookmarks.swift
//  TobyTunes
//
//  Created by Toby Nelson on 15/07/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import Foundation
import UIKit
import MediaPlayer

/// Wraps NSKeyedArchiver / NSKeyedUnarchiver using the secure-coding APIs.
/// Only Foundation property-list types are stored, so existing saved bookmarks still decode.
enum ArchiveHelper {
    static let allowedClasses: [AnyClass] = [NSDictionary.self, NSMutableDictionary.self,
                                             NSArray.self, NSNumber.self, NSString.self, NSData.self]

    static func unarchiveDictionary(_ data: Data) -> NSDictionary {
        do {
            if let dictionary = try NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data) as? NSDictionary {
                return dictionary
            }
        } catch {
            print("Failed to unarchive: \(error)")
        }
        return NSDictionary()
    }

    static func archive(_ dictionary: NSDictionary) -> Data {
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: dictionary, requiringSecureCoding: true)
        } catch {
            print("Failed to archive: \(error)")
            return Data()
        }
    }
}

enum EPlaylistType: Int {
    case Album = 1, Artist, Unknown, None, UserPlaylist
}

struct Playlist {
    var type: EPlaylistType
    var artistPersistentID: UInt64
    var albumPersistentID: UInt64
    var trackPersistentID: UInt64
    var mediaItemIDs: [UInt64]
    var representativeItemID: UInt64

    var title: String
    var details: String
    
    var totalDuration: TimeInterval

    /// For a user playlist: the playlist's ID (UUID string).
    var userPlaylistID: String = ""
    /// Whether mediaItemIDs is in shuffled order.
    var isShuffled: Bool = false
    /// When shuffled: the normal order, so shuffle can be turned off after resuming.
    var unshuffledItemIDs: [UInt64] = []

    init() {
        type = .None
        artistPersistentID = 0
        albumPersistentID = 0
        trackPersistentID = 0
        mediaItemIDs = []
        representativeItemID = 0
        title = ""
        details = ""
        totalDuration = -1.0
    }

    func containsTrackID(trackID: UInt64) -> Bool {
        return mediaItemIDs.contains(trackID)
    }

    /// Whether two lists are the same thing being played, so a bookmark keeps following its list when
    /// it's shuffled and, for a user playlist, after the playlist has been edited.
    func isSameSource(as other: Playlist) -> Bool {
        if type == .UserPlaylist || other.type == .UserPlaylist {
            return type == other.type && userPlaylistID == other.userPlaylistID
        }
        return mediaItemIDs.count == other.mediaItemIDs.count && mediaItemIDs.sorted() == other.mediaItemIDs.sorted()
    }

    init(data: Data) {
        let dictionary = ArchiveHelper.unarchiveDictionary(data)
        type = EPlaylistType( rawValue: (dictionary["type"] as! NSNumber).intValue )!
        artistPersistentID = (dictionary["artistPersistentID"] as! NSNumber).uint64Value
        albumPersistentID = (dictionary["albumPersistentID"] as! NSNumber).uint64Value
        trackPersistentID = (dictionary["trackPersistentID"] as! NSNumber).uint64Value
        let mediaItemIDList = dictionary["mediaItemIDs"] as! [NSNumber]
        mediaItemIDs = mediaItemIDList.map { $0.uint64Value }
        representativeItemID = (dictionary["representativeItemID"] as! NSNumber).uint64Value
        title = dictionary["title"] as! String
        details = dictionary["details"] as! String
        totalDuration = dictionary["totalDuration"] as! TimeInterval
        // Added in 1.7 (missing from older bookmarks)
        userPlaylistID = (dictionary["userPlaylistID"] as? String) ?? ""
        isShuffled = (dictionary["isShuffled"] as? NSNumber)?.boolValue ?? false
        unshuffledItemIDs = ((dictionary["unshuffledItemIDs"] as? [NSNumber]) ?? []).map { $0.uint64Value }
    }

    func encode() -> Data {
        let dictionary = NSMutableDictionary()
        dictionary["type"] = NSNumber(value: type.rawValue)
        dictionary["artistPersistentID"] = NSNumber( value: artistPersistentID )
        dictionary["albumPersistentID"] = NSNumber( value: albumPersistentID )
        dictionary["trackPersistentID"] = NSNumber( value: trackPersistentID )
        dictionary["mediaItemIDs"] = mediaItemIDs.map { NSNumber(value: $0) }
        dictionary["representativeItemID"] = NSNumber( value: representativeItemID )
        dictionary["title"] = title
        dictionary["details"] = details
        dictionary["totalDuration"] = totalDuration
        dictionary["userPlaylistID"] = userPlaylistID
        dictionary["isShuffled"] = NSNumber(value: isShuffled)
        dictionary["unshuffledItemIDs"] = unshuffledItemIDs.map { NSNumber(value: $0) }

        return ArchiveHelper.archive(dictionary)
    }
}

struct Bookmark {
    static var nextId = 1000

    var id: Int
    var playlist: Playlist
    var currentItemIndex: Int
    var currentTrackTime: TimeInterval
    var currentTrackDuration: TimeInterval

    static func getNextId() -> Int {
        Bookmark.nextId = Bookmark.nextId + 1
        return Bookmark.nextId
    }

    init(playlist: Playlist,
         currentItemIndex: Int,
         currentTrackTime: TimeInterval,
         currentTrackDuration: TimeInterval) {
        self.id = Bookmark.getNextId()
        self.playlist = playlist
        self.currentItemIndex = currentItemIndex
        self.currentTrackTime = currentTrackTime
        self.currentTrackDuration = currentTrackDuration
    }

    func elapsedTime() -> Double {
        let mediaItems = MusicLibrary.getMediaItems(itemIDs: Array(self.playlist.mediaItemIDs[0..<currentItemIndex]))
        var totalDuration = 0.0
        for item in mediaItems {
            totalDuration += item.playbackDuration
        }
        totalDuration += self.currentTrackTime
        return totalDuration
    }

    init(data: Data) {
        let dictionary = ArchiveHelper.unarchiveDictionary(data)

        id = Bookmark.getNextId()
        playlist = Playlist( data: dictionary["playlist"] as! Data )
        currentItemIndex = (dictionary["currentItemIndex"] as! NSNumber).intValue
        currentTrackTime = (dictionary["currentTrackTime"] as! TimeInterval)
        currentTrackDuration = (dictionary["currentTrackDuration"] as! TimeInterval)
    }

    func encode() -> Data {
        let dictionary = NSMutableDictionary()
        dictionary["playlist"] = playlist.encode()
        dictionary["currentItemIndex"] = NSNumber( value: currentItemIndex )
        dictionary["currentTrackTime"] = currentTrackTime
        dictionary["currentTrackDuration"] = currentTrackDuration

        return ArchiveHelper.archive(dictionary)
    }

    func containsTrackID(trackID: UInt64) -> Bool {
        return playlist.containsTrackID(trackID: trackID)
    }
}

struct BookmarkData {
    var version: Int = 2
    var currentPlaylist = Playlist()
    var marks: [Bookmark] = []

    mutating func decode(data: Data) {
        let dictionary = ArchiveHelper.unarchiveDictionary(data)
        if dictionary["version"] == nil {
            return
        }
        version = (dictionary["version"] as! NSNumber).intValue
        let marksData = dictionary["marks"] as! [Data]
        self.marks = marksData.map { Bookmark( data:$0 ) }
    }

    func encode() -> Data {
        let dictionary = NSMutableDictionary()
        dictionary["version"] = NSNumber( value: version )
        dictionary["marks"] = marks.map { $0.encode() }

        return ArchiveHelper.archive(dictionary)
    }
}

struct Bookmarks {
    static var data = BookmarkData()

    /// The bookmark for the list that's playing, if it has one. Only this bookmark follows playback, so a
    /// song that's in several bookmarked lists only moves the one being listened to.
    static var currentBookmarkId: Int? = nil

    static func getBookmarkData() -> BookmarkData {
        return Bookmarks.data
    }

    static func count() -> Int {
        return Bookmarks.data.marks.count
    }

    static func getBookmarkAtIndex(index: Int) -> Bookmark? {
        if (index >= 0) && (index < Bookmarks.data.marks.count) {
            return Bookmarks.data.marks[index]
        }
        return nil
    }

    /// Puts the bookmarks in a new order (after the user rearranges them). IDs not given keep their
    /// place at the end.
    static func setOrder(_ ids: [Int]) {
        var reordered = ids.compactMap { id in data.marks.first { $0.id == id } }
        reordered += data.marks.filter { mark in !ids.contains(mark.id) }
        guard reordered.map({ $0.id }) != data.marks.map({ $0.id }) else { return }
        data.marks = reordered
        save()
    }

    static func addBookmark(newBookmark: Bookmark) {
        Bookmarks.data.marks.insert(newBookmark, at: 0)
        save()
    }

    static func setCurrentPlaylist(type: EPlaylistType,
                                   persistentID: MPMediaEntityPersistentID,
                                   title: String,
                                   details: String,
                                   representativeItem: MPMediaItem,
                                   mediaItems: [MPMediaItem],
                                   userPlaylistID: String = "") {
        var result = Playlist()
        result.type = type
        result.userPlaylistID = userPlaylistID
        if result.type == .Artist {
            result.artistPersistentID = persistentID
        }
        else if result.type == .Album {
            result.albumPersistentID = persistentID
        }
        else if result.type == .Unknown {
            result.trackPersistentID = persistentID
        }

        result.title = title
        result.details = details

        var duration = 0.0
        for item in mediaItems {
            result.mediaItemIDs.append(item.persistentID)
            duration += item.playbackDuration
        }
        result.totalDuration = duration
        result.representativeItemID = representativeItem.persistentID
        data.currentPlaylist = result

        // If this list is bookmarked, its bookmark follows playback from now on
        currentBookmarkId = playerIsPlaying(result) ? findBookmark(matching: result)?.id : nil
    }

    /// Whether the player's queue is this list (in any order).
    static func playerIsPlaying(_ playlist: Playlist) -> Bool {
        let queueIDs = Player.sharedInstance.queueItemIDs
        return !queueIDs.isEmpty
            && queueIDs.count == playlist.mediaItemIDs.count
            && queueIDs.sorted() == playlist.mediaItemIDs.sorted()
    }

    static func findBookmark(matching playlist: Playlist) -> Bookmark? {
        return data.marks.first { $0.playlist.isSameSource(as: playlist) }
    }

    static func createBookmark(playlist: Playlist) -> Bookmark? {
        if playlist.type == .None || playlist.mediaItemIDs.isEmpty {
            return nil
        }

        let player = Player.sharedInstance
        guard let trackID = player.nowPlayingID,
              let currentTrackTime = player.getCurrentTime(),
              let currentTrackDuration = player.getCurrentDuration() else { return nil }

        var list = playlist
        var itemIndex: Int? = nil
        if playerIsPlaying(playlist), let queueIndex = player.indexNowPlaying {
            // Remember the order being played, which may be shuffled
            list.mediaItemIDs = player.queueItemIDs
            list.isShuffled = player.isShuffled
            list.unshuffledItemIDs = player.isShuffled ? player.unshuffledItemIDs : []
            itemIndex = queueIndex
        }
        else {
            itemIndex = playlist.mediaItemIDs.firstIndex(of: trackID)
        }

        guard let currentItemIndex = itemIndex else { return nil }
        return Bookmark(playlist: list, currentItemIndex: currentItemIndex, currentTrackTime: currentTrackTime, currentTrackDuration: currentTrackDuration)
    }

    @discardableResult 
    static func addCurrentPlaylistAsBookmark() -> Bool {
        let playlist = data.currentPlaylist
        if let existing = findBookmark(matching: playlist) {
            if playerIsPlaying(playlist) {
                currentBookmarkId = existing.id
            }
            return false
        }

        if let bookmark = createBookmark(playlist: playlist) {
            addBookmark(newBookmark: bookmark)
            if playerIsPlaying(playlist) {
                currentBookmarkId = bookmark.id
            }
            return true
        }
        return false
    }

    /// Starts playing a bookmark from where it was left. Returns false if none of its songs can be played.
    @discardableResult
    static func resumeBookmark(bookmarkId: Int) -> Bool {
        guard let markIndex = findMarkIndexWithId(bookmarkId: bookmarkId) else { return false }
        var mark = data.marks[markIndex]

        // A playlist may have been edited since it was bookmarked
        if mark.playlist.type == .UserPlaylist,
           let playlistID = UUID(uuidString: mark.playlist.userPlaylistID),
           let userPlaylist = UserPlaylists.shared.playlist(id: playlistID) {
            reconcile(&mark, with: userPlaylist)
        }

        // Skip songs that are no longer in the library, keeping the place
        let available = Set(MusicLibrary.getMediaItems(itemIDs: mark.playlist.mediaItemIDs).map { $0.persistentID })
        var kept: [UInt64] = []
        var itemIndex = 0
        var trackTime = mark.currentTrackTime
        var placed = false
        for (position, itemID) in mark.playlist.mediaItemIDs.enumerated() {
            if position == mark.currentItemIndex {
                itemIndex = kept.count
                placed = true
                if !available.contains(itemID) {
                    // The song has gone: carry on with the next one, from its start
                    trackTime = 0.0
                }
            }
            if available.contains(itemID) {
                kept.append(itemID)
            }
        }
        guard !kept.isEmpty else { return false }
        if !placed || itemIndex >= kept.count {
            itemIndex = 0
            trackTime = 0.0
        }

        if kept.count != mark.playlist.mediaItemIDs.count {
            mark.playlist.mediaItemIDs = kept
            mark.playlist.unshuffledItemIDs = mark.playlist.unshuffledItemIDs.filter { available.contains($0) }
        }
        mark.currentItemIndex = itemIndex
        mark.currentTrackTime = trackTime
        data.marks[markIndex] = mark
        save()

        let player = Player.sharedInstance
        player.pause()
        if mark.playlist.isShuffled && !mark.playlist.unshuffledItemIDs.isEmpty {
            player.setQueue(items: kept, unshuffled: mark.playlist.unshuffledItemIDs)
        }
        else {
            player.setQueue(items: kept)
        }
        player.setTrack(index: itemIndex)
        player.setCurrentTime(time: trackTime)
        player.play()

        data.currentPlaylist = mark.playlist
        currentBookmarkId = mark.id
        return true
    }

    /// Brings a playlist's bookmark up to date after the playlist has been edited: songs since removed
    /// are dropped and songs since added are included, keeping the place.
    static func reconcile(_ mark: inout Bookmark, with userPlaylist: UserPlaylist) {
        mark.playlist.title = userPlaylist.name

        let oldIDs = mark.playlist.mediaItemIDs
        let newIDs = userPlaylist.trackIDs
        let oldIndex = mark.currentItemIndex
        // An emptied playlist: keep playing what was bookmarked
        guard !newIDs.isEmpty else { return }

        var newOrder: [UInt64] = []
        var newIndex: Int? = nil
        var currentKept = false

        if mark.playlist.isShuffled {
            // Keep the shuffled order: drop removed songs, and add new songs at the end
            var remaining: [UInt64: Int] = [:]
            for itemID in newIDs {
                remaining[itemID, default: 0] += 1
            }
            for (position, itemID) in oldIDs.enumerated() {
                let stillThere = (remaining[itemID] ?? 0) > 0
                if position == oldIndex {
                    // If this song has gone, the next song takes its place
                    newIndex = newOrder.count
                    currentKept = stillThere
                }
                if stillThere {
                    remaining[itemID]! -= 1
                    newOrder.append(itemID)
                }
            }
            for itemID in newIDs where (remaining[itemID] ?? 0) > 0 {
                remaining[itemID]! -= 1
                newOrder.append(itemID)
            }
            mark.playlist.unshuffledItemIDs = newIDs
        }
        else {
            // Follow the playlist's order, finding the same song again
            newOrder = newIDs
            if oldIndex >= 0 && oldIndex < oldIDs.count {
                let currentID = oldIDs[oldIndex]
                // Which copy of the song it was, if it's in the playlist more than once
                let occurrence = oldIDs[..<oldIndex].filter { $0 == currentID }.count
                let matches = newIDs.indices.filter { newIDs[$0] == currentID }
                if !matches.isEmpty {
                    newIndex = matches[min(occurrence, matches.count - 1)]
                    currentKept = true
                }
                else {
                    // The song was removed: carry on with the next song that's still in the playlist
                    for itemID in oldIDs[(oldIndex + 1)...] {
                        if let index = newIDs.firstIndex(of: itemID) {
                            newIndex = index
                            break
                        }
                    }
                }
            }
        }

        if !currentKept {
            mark.currentTrackTime = 0.0
        }
        if let index = newIndex, index < newOrder.count {
            mark.currentItemIndex = index
        }
        else {
            mark.currentItemIndex = 0
            mark.currentTrackTime = 0.0
        }
        if newOrder != oldIDs {
            mark.playlist.mediaItemIDs = newOrder
            mark.playlist.totalDuration = MusicLibrary.getMediaItems(itemIDs: newOrder).reduce(0.0) { $0 + $1.playbackDuration }
        }
    }

    private static func isBookmark(_ mark: Bookmark, forUserPlaylistID key: String) -> Bool {
        return mark.playlist.type == .UserPlaylist && mark.playlist.userPlaylistID == key
    }

    static func hasBookmark(forUserPlaylistID id: UUID) -> Bool {
        return data.marks.contains { isBookmark($0, forUserPlaylistID: id.uuidString) }
    }

    /// When a playlist is deleted, its bookmark goes too. If the playlist is what's playing, the music
    /// carries on, but there's no longer anything to bookmark: the bookmark button is unavailable
    /// until something else is played.
    static func userPlaylistDeleted(id: UUID) {
        let key = id.uuidString
        let removedIDs = data.marks.filter { isBookmark($0, forUserPlaylistID: key) }.map { $0.id }
        if !removedIDs.isEmpty {
            data.marks.removeAll { isBookmark($0, forUserPlaylistID: key) }
            if let current = currentBookmarkId, removedIDs.contains(current) {
                currentBookmarkId = nil
            }
            save()
        }
        if data.currentPlaylist.type == .UserPlaylist && data.currentPlaylist.userPlaylistID == key {
            data.currentPlaylist = Playlist()
        }
    }

    /// Whether what's playing can be bookmarked: not when it came from a playlist that's since been deleted.
    static var canBookmarkCurrentPlaylist: Bool {
        return Player.sharedInstance.nowPlayingID != nil && data.currentPlaylist.type != .None
    }

    /// Removes bookmarks for playlists that no longer exist (from before deleting a playlist also
    /// removed its bookmark). Run at launch, after loading.
    static func removeOrphanedPlaylistBookmarks() {
        let existing = Set(UserPlaylists.shared.playlists.map { $0.id.uuidString })
        let before = data.marks.count
        data.marks.removeAll { $0.playlist.type == .UserPlaylist && !existing.contains($0.playlist.userPlaylistID) }
        if data.marks.count != before {
            save()
        }
    }

    /// Keeps bookmark titles in step when a playlist is renamed.
    static func userPlaylistRenamed(id: UUID, name: String) {
        let key = id.uuidString
        var updated = false
        for index in data.marks.indices where data.marks[index].playlist.type == .UserPlaylist && data.marks[index].playlist.userPlaylistID == key {
            data.marks[index].playlist.title = name
            updated = true
        }
        if data.currentPlaylist.type == .UserPlaylist && data.currentPlaylist.userPlaylistID == key {
            data.currentPlaylist.title = name
        }
        if updated {
            save()
        }
    }

    static func findBookmarkIdWithTrackID(persistentId: UInt64) -> Int? {
        for mark in data.marks {
            for itemID in mark.playlist.mediaItemIDs {
                if itemID == persistentId {
                    return mark.id
                }
            }
        }
        return nil
    }

    static func findMarkIndexWithId(bookmarkId: Int) -> Int? {
        for (index, mark) in data.marks.enumerated() {
            if mark.id == bookmarkId {
                return index
            }
        }
        return nil
    }

    static func findMarkWithId(bookmarkId: Int) -> Bookmark? {
        if let index = Bookmarks.findMarkIndexWithId(bookmarkId: bookmarkId) {
            return data.marks[index]
        }
        return nil
    }

    @discardableResult 
    static func removeBookmark(bookmarkId: Int) -> Int? {
        if let index = Bookmarks.findMarkIndexWithId(bookmarkId: bookmarkId) {
            data.marks.remove(at: index)
            if currentBookmarkId == bookmarkId {
                currentBookmarkId = nil
            }
            save()
            return index
        }
        return nil
    }

    @discardableResult
    static func resetBookmark(bookmarkId: Int) -> Int? {
        if let index = Bookmarks.findMarkIndexWithId(bookmarkId: bookmarkId) {
            data.marks[index].currentItemIndex = 0
            data.marks[index].currentTrackTime = 0.0
            save()
            return index
        }
        return nil
    }

    static func isTrackIDInCurrentPlaylist(mediaItemID: UInt64) -> Bool {
        for itemID in data.currentPlaylist.mediaItemIDs {
            if mediaItemID == itemID {
                return true
            }
        }

        return false
    }

    static func isPlaylistAlreadyBookmarked(playlist: Playlist) -> Bool {
        return findBookmark(matching: playlist) != nil
    }

    /// Saves the playing position into the bookmark for the list that's playing (if it has one).
    static func updateBookmarks() {
        guard let bookmarkId = currentBookmarkId,
              let markIndex = findMarkIndexWithId(bookmarkId: bookmarkId) else { return }
        let player = Player.sharedInstance
        guard player.nowPlayingID != nil,
              let currentTrackTime = player.getCurrentTime(),
              let currentItemIndex = player.indexNowPlaying,
              let currentTrackDuration = player.getCurrentDuration() else { return }

        var mark = data.marks[markIndex]
        var updated = false
        if ((mark.currentItemIndex != currentItemIndex) ||
            (mark.currentTrackTime != currentTrackTime) ||
            (mark.currentTrackDuration != currentTrackDuration)) {
            mark.currentItemIndex = currentItemIndex
            mark.currentTrackTime = currentTrackTime
            mark.currentTrackDuration = currentTrackDuration
            updated = true
        }

        // Keep the bookmark's order in step with the player's, e.g. after shuffle is turned on or off
        if mark.playlist.isShuffled != player.isShuffled ||
            !mark.playlist.mediaItemIDs.elementsEqual(player.queue.tracks.lazy.map { $0.persistentID }) {
            mark.playlist.mediaItemIDs = player.queueItemIDs
            mark.playlist.isShuffled = player.isShuffled
            mark.playlist.unshuffledItemIDs = player.isShuffled ? player.unshuffledItemIDs : []
            updated = true
        }

        if updated {
            data.marks[markIndex] = mark
            save()
        }
    }

    static var bookmarksURL: URL? = nil

    static func bookmarkStorageFilename() -> URL? {
        if bookmarksURL == nil {
            if let dataURL = Utilities.applicationDataDirectory() {
                bookmarksURL = dataURL.appendingPathComponent("bookmark.dat", isDirectory: false)
                return bookmarksURL
            }
            return nil
        }
        return bookmarksURL!
    }

    static func containsTrack(trackID: UInt64) -> Bool {
        for mark in data.marks {
            for track in mark.playlist.mediaItemIDs {
                if track == trackID {
                    return true
                }
            }
        }
        return false
    }

    static func save() {
        // Save to storage
        if let bookmarksURL = bookmarkStorageFilename() {
            do {
                try data.encode().write(to: bookmarksURL, options: Data.WritingOptions.atomicWrite)
            } catch let error as NSError {
                print(error.description)
            }
        }
    }

    static func load() {
        // Load from storage
        data.marks.removeAll()
        if let bookmarksURL = bookmarkStorageFilename() {
            do {
                let readData = try Data(contentsOf: bookmarksURL)
                data.decode( data: readData )
            } catch let error as NSError {
                print(error.description)
            }
        }
    }
}

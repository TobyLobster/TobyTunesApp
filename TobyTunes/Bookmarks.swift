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

enum EPlaylistType: Int {
    case Album = 1, Artist, Unknown, None
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

    init(data: Data) {
        let dictionary = NSKeyedUnarchiver.unarchiveObject(with: data) as! NSDictionary
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

        return NSKeyedArchiver.archivedData(withRootObject: dictionary)
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
        let dictionary = NSKeyedUnarchiver.unarchiveObject(with: data) as! NSDictionary

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

        return NSKeyedArchiver.archivedData(withRootObject: dictionary)
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
        let dictionary = NSKeyedUnarchiver.unarchiveObject(with: data) as! NSDictionary
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

        return NSKeyedArchiver.archivedData(withRootObject: dictionary)
    }
}

struct Bookmarks {
    static var data = BookmarkData()

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

    static func addBookmark(newBookmark: Bookmark) {
        Bookmarks.data.marks.insert(newBookmark, at: 0)
        save()
    }

    static func setCurrentPlaylist(type: EPlaylistType,
                                   persistentID: MPMediaEntityPersistentID,
                                   title: String,
                                   details: String,
                                   representativeItem: MPMediaItem,
                                   mediaItems: [MPMediaItem]) {
        var result = Playlist()
        result.type = type
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
    }

    static func createBookmark(playlist: Playlist) -> Bookmark? {
        if data.currentPlaylist.type == .None {
            return nil
        }
        if data.currentPlaylist.mediaItemIDs.count == 0 {
            return nil
        }

        if let currentTrackTime             = Player.sharedInstance.getCurrentTime() {
            if let currentItemIndex         = Player.sharedInstance.indexNowPlaying {
                if let currentTrackDuration = Player.sharedInstance.getCurrentDuration() {
                    return Bookmark(playlist: playlist, currentItemIndex: currentItemIndex, currentTrackTime: currentTrackTime, currentTrackDuration: currentTrackDuration)
                }
            }
        }
        return nil
    }

    static func addCurrentPlaylistAsBookmark() -> Bool {
        if isPlaylistAlreadyBookmarked(playlist: data.currentPlaylist) {
            return false
        }

        if let bookmark = createBookmark(playlist: data.currentPlaylist) {
            addBookmark(newBookmark: bookmark)
            return true
        }
        return false
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

    static func removeBookmark(bookmarkId: Int) -> Int? {
        if let index = Bookmarks.findMarkIndexWithId(bookmarkId: bookmarkId) {
            data.marks.remove(at: index)
            save()
            return index
        }
        return nil
    }

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
        for mark in data.marks {
            if mark.playlist.mediaItemIDs.count == playlist.mediaItemIDs.count {
                var identical = true
                for (index, itemID) in mark.playlist.mediaItemIDs.enumerated() {
                    if playlist.mediaItemIDs[index] != itemID {
                        identical = false
                        break
                    }
                }

                if identical {
                    return true
                }
            }
        }

        return false
    }

    static func updateBookmarks() {
        guard let persistentId         = Player.sharedInstance.nowPlayingID else { return }
        guard let currentTrackTime     = Player.sharedInstance.getCurrentTime() else { return }
        guard let currentItemIndex     = Player.sharedInstance.indexNowPlaying else { return }
        guard let currentTrackDuration = Player.sharedInstance.getCurrentDuration() else { return }

        var updated = false
        for (markIndex, mark) in data.marks.enumerated() {
            for itemID in mark.playlist.mediaItemIDs {
                if itemID == persistentId {
                    if ((mark.currentItemIndex != currentItemIndex) ||
                        (mark.currentTrackTime != currentTrackTime) ||
                        (mark.currentTrackDuration != currentTrackDuration)) {
                        data.marks[markIndex].currentItemIndex = currentItemIndex
                        data.marks[markIndex].currentTrackTime = currentTrackTime
                        data.marks[markIndex].currentTrackDuration = currentTrackDuration
                        updated = true
                    }
                }
            }
        }

        if updated {
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

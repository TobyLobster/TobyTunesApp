//
//  MusicLibrary.swift
//  TobyTunes
//
//  Created by Toby Nelson on 14/07/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import Foundation
import MediaPlayer

struct GenreData {
    var genres : [MPMediaItemCollection]
    var artistCounts: [Int]
}

struct ArtistsData {
    var artists : [MPMediaItemCollection]
    var albumCounts: [Int]
}

struct AlbumsData {
    var albums : [MPMediaItemCollection]
    var trackCounts: [Int]
}

struct SingleAlbumData {
    var items : [MPMediaItem]
    var representativeItem: MPMediaItem?
}

struct SingleArtistData {
    var items : [MPMediaItem]
    var representativeItem: MPMediaItem?
}

class MusicLibrary {
    static var libraryDate: Date = Date(timeIntervalSince1970: 0)
    static var items: [MPMediaItem] = []

    static func artistForItem(item: MPMediaItem?) -> String {
        if let artist = item?.albumArtist {
            return artist
        }
        if let artist = item?.artist {
            return artist
        }
        return ""
    }

    static func optionalArtistForItem(item: MPMediaItem?) -> String? {
        if let artist = item?.albumArtist {
            return artist
        }
        if let artist = item?.artist {
            return artist
        }
        return nil
    }

    static func getGenericQuery(cloudItems: Bool) -> MPMediaQuery {
        let query = MPMediaQuery(filterPredicates: nil)
        let mediaTypePredicate = MPMediaPropertyPredicate(value: MPMediaType.anyAudio.rawValue, forProperty: MPMediaItemPropertyMediaType )
        query.addFilterPredicate(mediaTypePredicate)
        let cloudPredicate = MPMediaPropertyPredicate(value: cloudItems, forProperty: MPMediaItemPropertyIsCloudItem)
        query.addFilterPredicate(cloudPredicate)
        return query
    }

    static func getLibraryItems() -> [MPMediaItem] {
        // Do we need to refresh the library?
        if MPMediaLibrary.default().lastModifiedDate != libraryDate {

            libraryDate = MPMediaLibrary.default().lastModifiedDate
            let query = getGenericQuery(cloudItems: false)
            let result = query.items
            if result == nil {
                items = []
            }
            else {
                items = result!
            }
        }
        return items
    }

    static func getMediaItems(itemIDs: [UInt64] ) -> [MPMediaItem] {
        var result: [MPMediaItem] = []

        for itemID in itemIDs {
            let query = MusicLibrary.getGenericQuery(cloudItems: false)
            query.addFilterPredicate( MPMediaPropertyPredicate(value: NSNumber(value: itemID), forProperty: MPMediaItemPropertyPersistentID ) )
            if query.items != nil && query.items!.count > 0 {
                result.append(query.items![0])
            }
        }
        return result
    }

    static func getGenreData() -> GenreData {
        let items = getLibraryItems()
        var result = GenreData(genres: [], artistCounts: [])

        // Create dictionary of items keyed by genre
        var dict: [String: [MPMediaItem]] = [:]
        for item in items {
            let key = Utilities.safeGetString(string: item.genre)

            if dict[key] == nil {
                dict[key] = [item]
            }
            else {
                dict[key]!.append(item)
            }
        }

        // Sort by genre name
        let sortedKeys = dict.keys.sorted { (a, b) -> Bool in
            if a == "" {
                return false
            }
            if b == "" {
                return true
            }
            return a.compare(b) == .orderedAscending
        }

        // Create collections
        for key in sortedKeys {
            let collection = MPMediaItemCollection(items: dict[key]!)
            result.genres.append(collection)
        }

        // Count artists in each genre
        for collection in result.genres {
            let tempSet = NSMutableSet()
            for item in collection.items {
                let artist = MusicLibrary.artistForItem(item: item)
                tempSet.add(artist)
            }
            result.artistCounts.append(tempSet.count)
        }
        return result
    }

    static func getArtistsData(genreTitle: String? = nil) -> ArtistsData {
        // Find the items with the given genre
        var items: [MPMediaItem]
        if genreTitle == nil {
            items = getLibraryItems()
        }
        else {
            items = getLibraryItems().filter { (item) -> Bool in
                let genre = Utilities.safeGetString(string: item.genre)
                return genre == genreTitle
            }
        }

        var result = ArtistsData(artists: [], albumCounts: [])

        // Group by artist (based on albumArtist or failing that, by artist)
        var dict: [String: [MPMediaItem]] = [:]
        for item in items {
            let key = MusicLibrary.artistForItem(item: item)

            if dict[key] == nil {
                dict[key] = [item]
            }
            else {
                dict[key]!.append(item)
            }
        }

        // Sort artists by name
        let sortedKeys = dict.keys.sorted { (a, b) -> Bool in
            if a == "" {
                return false
            }
            if b == "" {
                return true
            }
            return a.compare(b) == .orderedAscending
        }

        // Sort each artist by album release date, album name, track number, track name
        for key in sortedKeys {
            let sortedItems = dict[key]!.sorted(by: { (a, b) -> Bool in

                // Compare release dates
                var result = Utilities.safeCompareDates(a: a.releaseDate, b: b.releaseDate)
                if result != .orderedSame {
                    return result == .orderedAscending
                }

                // Compare album titles
                result = Utilities.safeCompare(a: a.albumTitle, b: b.albumTitle)
                if result != .orderedSame {
                    return result == .orderedAscending
                }

                // Compare track numbers
                if a.albumTrackNumber < b.albumTrackNumber {
                    return true
                }
                if a.albumTrackNumber > b.albumTrackNumber {
                    return false
                }

                // Compare track names
                result = Utilities.safeCompare(a: a.title, b: b.title)
                if result != .orderedSame {
                    return result == .orderedAscending
                }
                return true
            })
            let collection = MPMediaItemCollection(items: sortedItems)
            result.artists.append(collection)
        }

        // Count albums by each artist
        for collection in result.artists {
            let tempSet = NSMutableSet()
            for item in collection.items {
                if let album = item.albumTitle {
                    tempSet.add(album)
                }
            }
            result.albumCounts.append(tempSet.count)
        }
        return result
    }

    static func getAlbumsData(genreTitle: String?, artistTitle: String) -> AlbumsData {
        // Find the items with the given genre and artist
        let items = getLibraryItems().filter { (item) -> Bool in
            let artist = MusicLibrary.artistForItem(item: item)

            if genreTitle == nil {
                return artist == artistTitle
            }
            let genre = Utilities.safeGetString(string: item.genre)
            return genre == genreTitle && artist == artistTitle
        }

        var result = AlbumsData(albums: [], trackCounts: [])

        // Group by album
        var dict: [String: [MPMediaItem]] = [:]
        for item in items {
            let key = Utilities.safeGetString(string: item.albumTitle)

            if dict[key] == nil {
                dict[key] = [item]
            }
            else {
                dict[key]!.append(item)
            }
        }

        // Sort albums by name
        let sortedKeys = dict.keys.sorted { (a, b) -> Bool in
            if a == "" {
                return false
            }
            if b == "" {
                return true
            }
            return a.compare(b) == .orderedAscending
        }

        // Sort each track by release date, album name, track number, track name
        for key in sortedKeys {
            let sortedItems = dict[key]!.sorted(by: { (a, b) -> Bool in

                // Compare release dates
                var result = Utilities.safeCompareDates(a: a.releaseDate, b: b.releaseDate)
                if result != .orderedSame {
                    return result == .orderedAscending
                }

                // Compare album titles
                result = Utilities.safeCompare(a: a.albumTitle, b: b.albumTitle)
                if result != .orderedSame {
                    return result == .orderedAscending
                }

                // Compare track numbers
                if a.albumTrackNumber < b.albumTrackNumber {
                    return true
                }
                if a.albumTrackNumber > b.albumTrackNumber {
                    return false
                }

                // Compare track names
                result = Utilities.safeCompare(a: a.title, b: b.title)
                if result != .orderedSame {
                    return result == .orderedAscending
                }
                return true
            })
            let collection = MPMediaItemCollection(items: sortedItems)
            result.albums.append(collection)
        }

        // Count tracks in each album
        for collection in result.albums {
            result.trackCounts.append(collection.items.count)
        }
        return result
    }

    static func getSingleAlbumData(genreTitle: String?, artistTitle: String, albumTitle: String) -> SingleAlbumData {
        // Find the items with the given genre, artist, and album
        var items = getLibraryItems().filter { (item) -> Bool in
            let genre  = Utilities.safeGetString(string: item.genre)
            let album  = Utilities.safeGetString(string: item.albumTitle)
            let artist = MusicLibrary.artistForItem(item: item)

            if genreTitle == nil {
                return artist == artistTitle && albumTitle == album
            }
            return genre == genreTitle && artist == artistTitle && albumTitle == album
        }

        items.sort { (a, b) -> Bool in
            // Compare track numbers
            if a.albumTrackNumber < b.albumTrackNumber {
                return true
            }
            if a.albumTrackNumber > b.albumTrackNumber {
                return false
            }

            // Compare track names
            let result = Utilities.safeCompare(a: a.title, b: b.title)
            if result != .orderedSame {
                return result == .orderedAscending
            }
            return true
        }
        let collection = MPMediaItemCollection(items: items)
        return SingleAlbumData(items: items, representativeItem: collection.representativeItem)
    }

    static func getSingleAlbumData(albumID: UInt64) -> SingleAlbumData {
        // Find the items with the given genre, artist, and album
        var items = getLibraryItems().filter { (item) -> Bool in
            return item.albumPersistentID == albumID
        }

        items.sort { (a, b) -> Bool in
            // Compare track numbers
            if a.albumTrackNumber < b.albumTrackNumber {
                return true
            }
            if a.albumTrackNumber > b.albumTrackNumber {
                return false
            }

            // Compare track names
            let result = Utilities.safeCompare(a: a.title, b: b.title)
            if result != .orderedSame {
                return result == .orderedAscending
            }
            return true
        }
        let collection = MPMediaItemCollection(items: items)
        return SingleAlbumData(items: items, representativeItem: collection.representativeItem)
    }
    
    static func getSingleArtistData(genreTitle: String?, artistTitle: String) -> SingleArtistData {
        let albumsData = getAlbumsData(genreTitle: genreTitle, artistTitle: artistTitle)

        var sortedArray: [MPMediaItem] = []
        for album in albumsData.albums {
            sortedArray.append(contentsOf: album.items)
        }
        let collection = MPMediaItemCollection(items: sortedArray)
        return SingleArtistData(items: sortedArray, representativeItem: collection.representativeItem)
    }

    static func resizeArtwork(artwork: MPMediaItemArtwork?, fitWithinSize: CGSize) -> UIImage? {
        return artwork?.image(at: fitWithinSize)?.resize(fitWithinSize: fitWithinSize)
    }
}

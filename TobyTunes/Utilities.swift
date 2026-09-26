//
//  Utilities.swift
//  TobyTunes
//
//  Created by Toby Nelson on 20/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import Foundation
import UIKit

extension UINavigationController {
    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
}

extension UITabBarController {
    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
}


struct Utilities {
    static func delay(delay:Double, closure:@escaping ()->()) {
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + delay) {
            closure()
        }
    }

    static func safeCompareDates(a: Date?, b: Date?) -> ComparisonResult {
        if a != nil {
            if b != nil {
                return a!.compare(b!)
            }
            return .orderedDescending
        }
        if b != nil {
            return .orderedAscending
        }
        return .orderedSame
    }

    static func safeCompare<T: Comparable>(a: T?, b: T?) -> ComparisonResult {
        if a != nil {
            if b != nil {
                if a! < b! {
                    return .orderedAscending
                }
                if a! > b! {
                    return .orderedDescending
                }
                return .orderedSame
            }
            return .orderedDescending
        }
        if b != nil {
            return .orderedAscending
        }
        return .orderedSame
    }

    static func safeGetString(string: String?) -> String {
        return string ?? ""
    }
    
    static func timeIntervalStringClockStyle(duration: Double) -> String {
        var d = duration + 0.5      // Round to nearest integer number of seconds
        let hours   = Int(d/(60 * 60))
        d -= Double(hours * 60 * 60)
        let minutes = Int(d/60)
        d -= Double(minutes * 60)
        let seconds = Int(d)
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        }
        return "\(seconds)s"
    }

    static func timeIntervalStringDHMSStyle(duration: Double) -> String {
        var d = duration + 0.5      // Round to nearest integer number of seconds
        let days    = Int(floor(d/(60*60*24)))
        d -= Double(days * (60*60*24))
        let hours   = Int(d/(60 * 60))
        d -= Double(hours * 60 * 60)
        let minutes = Int(d/60)
        d -= Double(minutes * 60)
        let seconds = Int(d)
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    
    static func scaledHeight(originalHeight: Float) -> Float {
        // choose the font size
        var newHeight = originalHeight
        let contentSize = UIApplication.shared.preferredContentSizeCategory

        switch( contentSize ) {
        case UIContentSizeCategory.extraSmall:
            newHeight = (12.0/16.0) * originalHeight
        case UIContentSizeCategory.small:
            newHeight = (14.0/16.0) * originalHeight
        case UIContentSizeCategory.medium:
            newHeight = (16.0/16.0) * originalHeight
        case UIContentSizeCategory.large:
            newHeight = (18.0/16.0) * originalHeight
        case UIContentSizeCategory.extraLarge:
            newHeight = (20.0/16.0) * originalHeight
        case UIContentSizeCategory.extraExtraLarge:
            newHeight = (22.0/16.0) * originalHeight
        case UIContentSizeCategory.extraExtraExtraLarge:
            newHeight = (24.0/16.0) * originalHeight
        case UIContentSizeCategory.accessibilityMedium:
            newHeight = (26.0/16.0) * originalHeight
        case UIContentSizeCategory.accessibilityLarge:
            newHeight = (28.0/16.0) * originalHeight
        case UIContentSizeCategory.accessibilityExtraLarge:
            newHeight = (30.0/16.0) * originalHeight
        case UIContentSizeCategory.accessibilityExtraExtraLarge:
            newHeight = (32.0/16.0) * originalHeight
        case UIContentSizeCategory.accessibilityExtraExtraExtraLarge:
            newHeight = (34.0/16.0) * originalHeight
        default:
            newHeight = originalHeight
        }

        return newHeight
    }

    static func fontSized(originalSize: Float) -> UIFont? {
        // choose the font size
        let fontSize = scaledHeight(originalHeight: originalSize)
        return UIFont.systemFont(ofSize: CGFloat(fontSize))
    }

    static func boldFontSized(originalSize: Float) -> UIFont? {
        // choose the font size
        let fontSize = scaledHeight(originalHeight: originalSize)
        return UIFont.boldSystemFont(ofSize: CGFloat(fontSize))
    }

    static func textTitleAttributes() -> [String : Any] {
        let style = NSMutableParagraphStyle()
        style.headIndent = 0
        return [convertFromNSAttributedStringKey(NSAttributedString.Key.font): Utilities.fontSized(originalSize: 17)! as Any, convertFromNSAttributedStringKey(NSAttributedString.Key.paragraphStyle): style]
    }

    static func textDetailsAttributes() -> [String : Any] {
        let style = NSMutableParagraphStyle()
        style.headIndent = 0
        return [convertFromNSAttributedStringKey(NSAttributedString.Key.font): Utilities.fontSized(originalSize: 15)! as Any, convertFromNSAttributedStringKey(NSAttributedString.Key.paragraphStyle): style]
    }

    static func measureText(text: String, attributes: [String : Any], width: CGFloat = CGFloat.greatestFiniteMagnitude) -> CGSize {
        let attributedText = NSAttributedString(string: text, attributes: convertToOptionalNSAttributedStringKeyDictionary(attributes))
        let textRect = attributedText.boundingRect( with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                            context: nil )
        return textRect.size
    }

    static func tableIndexToDataIndex(tableIndex: Int, columns: Int, total: Int) -> Int {
        if tableIndex < 0 {
            return -1
        }
        let column = tableIndex % columns
        let row    = tableIndex / columns

        let maxEntriesPerColumn = (total + columns - 1) / columns
        var fullColumns = total % columns
        if fullColumns == 0 { fullColumns = columns }

        if column < fullColumns {
            return (column * maxEntriesPerColumn) + row
        }
        let result = ((fullColumns * maxEntriesPerColumn) + ((column - fullColumns) * (maxEntriesPerColumn - 1))) + row
        assert(tableIndex == dataIndexToTableIndex(dataIndex: result, columns: columns, total: total))
        return result
    }

    static func dataIndexToTableIndex(dataIndex: Int, columns: Int, total: Int) -> Int {
        if dataIndex < 0 {
            return -1
        }
        let maxEntriesPerColumn = (total + columns - 1) / columns
        var fullColumns = total % columns
        if fullColumns == 0 { fullColumns = columns }
        let fullEntries = fullColumns * maxEntriesPerColumn

        // If less than the full columns, use those
        if dataIndex < fullEntries {
            let row    = dataIndex % maxEntriesPerColumn
            let column = dataIndex / maxEntriesPerColumn
            return row * columns + column
        }

        // Look through the remaining less than full columns
        let extraDataIndex = dataIndex - fullEntries
        let row    = extraDataIndex % (maxEntriesPerColumn-1)
        let column = fullColumns + (extraDataIndex / (maxEntriesPerColumn-1))
        return row * columns + column
    }
    
    /// Approximate points per physical inch. Points are almost the same physical size across
    /// each device family: current iPhones are ~153 (460 ppi at 3x; older models 163),
    /// iPads are 132 (264 ppi at 2x; the iPad mini is 163).
    static func pointsPerInch() -> Double {
        return UIDevice.current.userInterfaceIdiom == .pad ? 132.0 : 153.0
    }

    /// Width of a collection view that content can use: its width less the left and right
    /// safe-area insets (the Dynamic Island / notch side and the matching inset opposite it in landscape).
    static func usableWidth(of collectionView: UICollectionView) -> CGFloat {
        let insets = collectionView.safeAreaInsets
        return max(0, collectionView.bounds.width - insets.left - insets.right)
    }

    /// Number of columns that fit in `size` (the view's size, in points) with each column
    /// at least `minColumnWidthInches` wide (set in Constants.swift). Uses the view's own width,
    /// so it is correct in Split View, Slide Over and Stage Manager, and needs no per-model lookup table.
    static func recalculateColumns(size: CGSize) -> Int {
        let availableWidthInches = Double(size.width) / pointsPerInch()
        return max(1, Int(availableWidthInches / minColumnWidthInches))
    }

    static func cellBackgroundColor(indexPath: IndexPath, currentlyPlayingTableIndex: Int) -> UIColor {
        if currentlyPlayingTableIndex == indexPath.row {
            return UIColor(red: 230.0/255.0, green:230.0/255.0, blue:230.0/255.0, alpha:1)
        }
        return UIColor(red: 255.0/255.0, green:255.0/255.0, blue:255.0/255.0, alpha:0.0)
    }

    static func applicationDataDirectory() -> URL? {
        let sharedFM = FileManager.default
        let possibleURLs = sharedFM.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        var appSupportDir:URL? = nil
        var appDirectory:URL? = nil

        if possibleURLs.count >= 1 {
            // Use the first directory (if multiple are returned)
            appSupportDir = possibleURLs[0]
        }

        // If a valid app support directory exists, add the
        // app's bundle ID to it to specify the final directory.
        if appSupportDir != nil {
            if let appBundleID = Bundle.main.bundleIdentifier {
                appDirectory = appSupportDir?.appendingPathComponent( appBundleID )
            }
        }

        if appDirectory != nil {
            Utilities.createFolderAtURL(folderURL: appDirectory!)
        }
        return appDirectory
    }

    @discardableResult
    static func createFolderAtURL(folderURL: URL) -> Bool {
        do {
            try FileManager().createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch let error as NSError {
            print(error.description)
            return false
        }
    }

    static func getArtistDisplayName(artist: String?) -> String {
        if artist == nil || artist == "" {
            return "(Unknown Artist)"
        }
        return artist!
    }

    static func getAlbumDisplayName(album: String?) -> String {
        if album == nil || album == "" {
            return "(Unknown Album)"
        }
        return album!
    }

    static func getTrackDisplayName(track: String?) -> String {
        if track == nil || track == "" {
            return "(Unknown Track)"
        }
        return track!
    }

    static func getGenreDisplayName(genre: String?) -> String {
        if genre == nil || genre == "" {
            return "(Unknown Genre)"
        }
        return genre!
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromNSAttributedStringKey(_ input: NSAttributedString.Key) -> String {
	return input.rawValue
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToOptionalNSAttributedStringKeyDictionary(_ input: [String: Any]?) -> [NSAttributedString.Key: Any]? {
	guard let input = input else { return nil }
	return Dictionary(uniqueKeysWithValues: input.map { key, value in (NSAttributedString.Key(rawValue: key), value)})
}

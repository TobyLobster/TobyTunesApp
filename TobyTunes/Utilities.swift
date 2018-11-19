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

extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
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
        return [NSFontAttributeName: Utilities.fontSized(originalSize: 17)! as Any, NSParagraphStyleAttributeName: style]
    }

    static func textDetailsAttributes() -> [String : Any] {
        let style = NSMutableParagraphStyle()
        style.headIndent = 0
        return [NSFontAttributeName: Utilities.fontSized(originalSize: 15)! as Any, NSParagraphStyleAttributeName: style]
    }

    static func measureText(text: String, attributes: [String : Any], width: CGFloat = CGFloat.greatestFiniteMagnitude) -> CGSize {
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textRect = attributedText.boundingRect( with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                            context: nil )
        return textRect.size
    }

    static func deviceInfo() -> (name: String, screenDiagonalInches: Float, dpi: Float)? {
        let device = UIDevice.current.modelName
        if (device.starts(with: "iPhone"))
        {
            switch (device) {
                case "iPhone1,1":  return ("iPhone 1",                    3.5, 163.0)
                case "iPhone1,2":  return ("iPhone 3G",                   3.5, 163.0)
                case "iPhone2,1":  return ("iPhone 3GS",                  3.5, 163.0)
                case "iPhone3,1":  return ("iPhone 4",                    3.5, 326.0)
                case "iPhone3,2":  return ("iPhone 4",                    3.5, 326.0)
                case "iPhone3,3":  return ("iPhone 4",                    3.5, 326.0)
                case "iPhone4,1":  return ("iPhone 4s",                   3.5, 326.0)
                case "iPhone5,1":  return ("iPhone 5",                    4.0, 326.0)
                case "iPhone5,2":  return ("iPhone 5",                    4.0, 326.0)
                case "iPhone5,3":  return ("iPhone 5c",                   4.0, 326.0)
                case "iPhone5,4":  return ("iPhone 5c",                   4.0, 326.0)
                case "iPhone6,1":  return ("iPhone 5s",                   4.0, 326.0)
                case "iPhone6,2":  return ("iPhone 5s",                   4.0, 326.0)
                case "iPhone7,1":  return ("iPhone 6 Plus",               5.5, 401.0)
                case "iPhone7,2":  return ("iPhone 6",                    4.7, 326.0)
                case "iPhone8,1":  return ("iPhone 6s",                   4.7, 326.0)
                case "iPhone8,2":  return ("iPhone 6s Plus",              5.5, 401.0)
                case "iPhone8,4":  return ("iPhone SE",                   4.0, 326.0)
                case "iPhone9,1":  return ("iPhone 7",                    4.7, 326.0)
                case "iPhone9,2":  return ("iPhone 7 Plus",               5.5, 401.0)
                case "iPhone9,3":  return ("iPhone 7",                    4.7, 326.0)
                case "iPhone9,4":  return ("iPhone 7 Plus",               5.5, 401.0)
                case "iPhone10,1": return ("iPhone 8",                    4.7, 326.0)
                case "iPhone10,2": return ("iPhone 8 Plus",               5.5, 401.0)
                case "iPhone10,3": return ("iPhone X",                    5.8, 458.0)
                case "iPhone10,4": return ("iPhone 8",                    4.7, 326.0)
                case "iPhone10,5": return ("iPhone 8 Plus",               5.5, 401.0)
                case "iPhone10,6": return ("iPhone X",                    5.8, 458.0)
                case "iPhone11,2": return ("iPhone XS",                   5.8, 458.0)
                case "iPhone11,4": return ("iPhone XS MAX",               6.5, 458.0)
                case "iPhone11,6": return ("iPhone XS MAX",               6.5, 458.0)
                case "iPhone11,8": return ("iPhone XR",                   6.1, 326.0)
                default: return ("iPhone Unknown",                        6.1, 326.0)
            }
        }
        else if (device.starts(with: "iPad"))
        {
            switch(device)
            {
                case "iPad1,1":   return ("iPad 1",                       9.7, 132.0)
                case "iPad2,1":   return ("iPad 2",                       9.7, 132.0)
                case "iPad2,2":   return ("iPad 2",                       9.7, 132.0)
                case "iPad2,3":   return ("iPad 2",                       9.7, 132.0)
                case "iPad2,4":   return ("iPad 2",                       9.7, 132.0)
                case "iPad2,5":   return ("iPad Mini 1",                  7.9, 163.0)
                case "iPad2,6":   return ("iPad Mini 1",                  7.9, 163.0)
                case "iPad2,7":   return ("iPad Mini 1",                  7.9, 163.0)
                case "iPad3,1":   return ("iPad 3",                       9.7, 264.0)
                case "iPad3,2":   return ("iPad 3",                       9.7, 264.0)
                case "iPad3,3":   return ("iPad 3",                       9.7, 264.0)
                case "iPad3,4":   return ("iPad 4",                       9.7, 264.0)
                case "iPad3,5":   return ("iPad 4",                       9.7, 264.0)
                case "iPad3,6":   return ("iPad 4",                       9.7, 264.0)
                case "iPad4,1":   return ("iPad Air 1",                   9.7, 264.0)
                case "iPad4,2":   return ("iPad Air 1",                   9.7, 264.0)
                case "iPad4,3":   return ("iPad Air 1",                   9.7, 264.0)
                case "iPad4,4":   return ("iPad Mini 2",                  7.9, 326.0)
                case "iPad4,5":   return ("iPad Mini 2",                  7.9, 326.0)
                case "iPad4,6":   return ("iPad Mini 2",                  7.9, 326.0)
                case "iPad4,7":   return ("iPad Mini 3",                  7.9, 326.0)
                case "iPad4,8":   return ("iPad Mini 3",                  7.9, 326.0)
                case "iPad4,9":   return ("iPad Mini 3",                  7.9, 326.0)
                case "iPad5,1":   return ("iPad Mini 4",                  7.9, 326.0)
                case "iPad5,2":   return ("iPad Mini 4",                  7.9, 326.0)
                case "iPad5,3":   return ("iPad Air 2",                   9.7, 264.0)
                case "iPad5,4":   return ("iPad Air 2",                   9.7, 264.0)
                case "iPad6,3":   return ("iPad Pro 9.7 Inch 1st Gen",    9.7, 264.0)
                case "iPad6,4":   return ("iPad Pro 9.7 Inch 1st Gen",    9.7, 264.0)
                case "iPad6,7":   return ("iPad Pro 12.9 Inch 1st Gen",  12.9, 264.0)
                case "iPad6,8":   return ("iPad Pro 12.9 Inch 1st Gen",  12.9, 264.0)
                case "iPad6,11":  return ("iPad 9.7 Inch 5th Gen",        9.7, 264.0)
                case "iPad6,12":  return ("iPad 9.7 Inch 5th Gen",        9.7, 264.0)
                case "iPad7,1":   return ("iPad Pro 12.9 Inch 2nd Gen",  12.9, 264.0)
                case "iPad7,2":   return ("iPad Pro 12.9 Inch 2nd Gen",  12.9, 264.0)
                case "iPad7,3":   return ("iPad Pro 10.5 Inch",          10.5, 264.0)
                case "iPad7,4":   return ("iPad Pro 10.5 Inch",          10.5, 264.0)
                case "iPad7,5":   return ("iPad 9.7 Inch 6th Gen",        9.7, 264.0)
                case "iPad7,6":   return ("iPad 9.7 Inch 6th Gen",        9.7, 264.0)
                default:          return ("iPad Unknown",                 9.7, 264.0)
            }
        }
        else if (device.starts(with: "iPod"))
        {
            switch(device)
            {
                case "iPod1,1": return ("iPod Touch 1",                   3.5, 163.0)
                case "iPod2,1": return ("iPod Touch 2",                   3.5, 163.0)
                case "iPod3,1": return ("iPod Touch 3",                   3.5, 163.0)
                case "iPod4,1": return ("iPod Touch 4",                   3.5, 326.0)
                case "iPod5,1": return ("iPod Touch 5",                   4.0, 326.0)
                case "iPod7,1": return ("iPod Touch 6",                   4.0, 326.0)
                default: return ("iPod Touch Unknown",                    4.0, 326.0)
            }
        }
        return nil
    }

    static func screenSizeInches() -> (Double, Double)? {
        if let info = deviceInfo() {
            let resolutionPoints = UIScreen.main.bounds.size
            let d = Double(info.screenDiagonalInches)
            let r = Double(resolutionPoints.width) / Double(resolutionPoints.height)
            let h = d / sqrt(1 + r*r)
            let w = r * h
            return (w, h)
        }
        return nil
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
    
    static func recalculateColumns(size: CGSize, minColumnWidthInches: Double) -> Int {
        if let info = Utilities.deviceInfo() {
            let d = Double(info.screenDiagonalInches)
            let r = Double(size.width) / Double(size.height)
            let h = d / sqrt(1 + r*r)
            let w = r * h
            let orientedSizeInches = (w, h)
            let availableWidthInches = orientedSizeInches.0
            var columns = Int(availableWidthInches / minColumnWidthInches)
            if columns <= 0 {
                columns = 1
            }
            return columns
        }
        return 1
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

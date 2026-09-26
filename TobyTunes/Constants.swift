//
//  Constants.swift
//  TobyTunes
//
//  Created by Toby Nelson on 20/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import UIKit

let thumbnailWidth  = 56
let thumbnailHeight = 56
let thumbnailCornerRadius: CGFloat = 8

/// The app's accent colour (Assets.xcassets/AccentColor): burnt red in light mode, a lighter tint in Dark Mode.
let accentColor = UIColor(named: "AccentColor") ?? UIColor(red: 0xC2/255.0, green: 0x41/255.0, blue: 0x0C/255.0, alpha: 1)
let thumbnailSize   = CGSize(width: CGFloat(thumbnailWidth), height: CGFloat(thumbnailHeight))

/// Minimum physical width of a column in the Albums, Album, Artists, Genres and Bookmarks lists.
/// Lists show as many columns as fit at this width (at least one).
let minColumnWidthInches = 2.0

//
//  TTBookmarkCollectionViewCell.swift
//  TobyTunes
//
//  Created by Toby Nelson on 27/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import Foundation
import UIKit

class TTBookmarkCollectionViewCell : UICollectionViewCell {
    @IBOutlet weak var bookmarkName: UILabel?
    @IBOutlet weak var bookmarkDetails: UILabel?
    @IBOutlet weak var bookmarkArt: UIImageView?
    @IBOutlet weak var bookmarkPlay: UIButton?
    @IBOutlet weak var bookmarkProgress: UIView?
    @IBOutlet weak var bookmarkWidthConstraint: NSLayoutConstraint?
}
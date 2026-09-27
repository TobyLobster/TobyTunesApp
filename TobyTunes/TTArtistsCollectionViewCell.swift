//
//  TTArtistsCollectionViewCell.swift
//  TobyTunes
//
//  Created by Toby Nelson on 27/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import Foundation
import UIKit

class TTArtistsCollectionViewCell : UICollectionViewCell {
    @IBOutlet weak var artistName: UILabel?
    @IBOutlet weak var artistDetails: UILabel?
    @IBOutlet weak var artistArt: UIImageView?
    @IBOutlet weak var artistPlay: UIButton?
    override func awakeFromNib() {
        super.awakeFromNib()
        Utilities.styleThumbnail(artistArt)
        Utilities.centreText(title: artistName, details: artistDetails, on: artistArt, in: self)
        Utilities.styleRowButton(artistPlay, systemName: "play.circle.fill", accessibilityLabel: "Play artist")
    }
}
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

    /// How far through the bookmark playback is, 0...1. Drives the width of bookmarkProgress.
    var progress: CGFloat = 1.0 {
        didSet { setNeedsLayout() }
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        updateProgressConstraint()
        super.layoutSubviews()
    }

    /// The progress bar's leading edge is 55pt inside the left layout margin, and the
    /// constraint's constant is measured from the right layout margin (-8 = the cell's right edge).
    /// The margins change with the safe area (e.g. 70pt beside the notch in landscape),
    /// so the available width is worked out from the current margins at layout time.
    private func updateProgressConstraint() {
        let margins = contentView.layoutMargins
        let fullWidth = max(0, contentView.bounds.width - margins.left - margins.right - 47)
        let clamped = min(1, max(0, progress))
        bookmarkWidthConstraint?.constant = -8 + (1 - clamped) * fullWidth
    }
}
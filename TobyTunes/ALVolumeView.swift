//
//  ALVolumeView.swift
//  TobyTunes
//
//  Created by Toby Nelson on 21/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import Foundation
import MediaPlayer

class ALVolumeView : MPVolumeView {
    override func layoutSubviews() {
        super.layoutSubviews()
        recursiveRemoveAnimationsOnView(view: self)
    }

    func recursiveRemoveAnimationsOnView(view: UIView) {
        view.layer.removeAllAnimations()
        for subview in view.subviews {
            self.recursiveRemoveAnimationsOnView(view: subview)
        }
    }
}

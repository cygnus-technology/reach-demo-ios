//
//  CircleButton.swift
//  Reach Sample
//
//  Created by Cygnus on 6/1/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import UIKit

class CircleButton: UIButton {
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layer.masksToBounds = true
    }
}

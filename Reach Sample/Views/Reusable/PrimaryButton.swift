//
//  PrimaryButton.swift
//  Reach Sample
//
//  Created by Cygnus on 6/1/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import UIKit

class PrimaryButton: UIButton {
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer.cornerRadius = 4
        layer.masksToBounds = true
    }
}

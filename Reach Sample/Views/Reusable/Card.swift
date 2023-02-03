//
//  Card.swift
//  Reach Sample
//
//  Created by Cygnus on 6/1/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import UIKit

class Card: UIView {
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .white
        layer.cornerRadius = 6
        layer.masksToBounds = true
    }
}

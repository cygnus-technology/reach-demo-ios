//
//  SessionView.swift
//  Reach Sample
//
//  Created by Cygnus on 11/22/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import UIKit

class SessionView: UIView {

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        clipsToBounds = true
        layer.cornerRadius = 12
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }
}

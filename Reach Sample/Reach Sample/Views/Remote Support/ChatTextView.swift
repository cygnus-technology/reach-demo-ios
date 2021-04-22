//
//  ChatTextLabel.swift
//  Reach Sample
//
//  Created by Cygnus on 3/8/21.
//  Copyright © 2021 Cygnus. All rights reserved.
//

import UIKit

class ChatTextView: UITextView {
    let topInset: CGFloat = 10.0
    let bottomInset: CGFloat = 10.0
    let leftInset: CGFloat = 10.0
    let rightInset: CGFloat = 10.0
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer.cornerRadius = 5
        layer.masksToBounds = true
        isUserInteractionEnabled = false
        textContainerInset = UIEdgeInsets(top: topInset, left: leftInset, bottom: bottomInset, right: rightInset)
    }
}

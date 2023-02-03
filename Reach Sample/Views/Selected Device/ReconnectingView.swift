//
//  ReconnectingBarItem.swift
//  Reach Sample
//
//  Created by Cygnus on 3/25/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import UIKit

class ReconnectingView: UIView {
    var activityIndicator: UIActivityIndicatorView?
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        translatesAutoresizingMaskIntoConstraints = false
        
        let activityIndicator = UIActivityIndicatorView()
        
        if #available(iOS 13.0, *) {
            activityIndicator.style = .medium
        } else {
            activityIndicator.style = .white
        }
        
        activityIndicator.color = .black
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.text = "Reconnecting"
        label.sizeToFit()
        label.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(label)
        addSubview(activityIndicator)
        addConstraints([
            NSLayoutConstraint(item: activityIndicator, attribute: .right, relatedBy: .equal, toItem: self, attribute: .right, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: label, attribute: .right, relatedBy: .equal, toItem: activityIndicator, attribute: .left, multiplier: 1, constant: -4),
            NSLayoutConstraint(item: activityIndicator, attribute: .centerY, relatedBy: .equal, toItem: self, attribute: .centerY, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: label, attribute: .centerY, relatedBy: .equal, toItem: self, attribute: .centerY, multiplier: 1, constant: 0)
        ])
        
        self.activityIndicator = activityIndicator
        self.activityIndicator?.startAnimating()
    }
}

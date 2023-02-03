//
//  RadioButton.swift
//  Reach Sample
//
//  Created by Cygnus on 12/15/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import UIKit

@IBDesignable class RadioButton: UIView {
    
    @IBInspectable var fillColor: UIColor = .black {
        didSet {
            setup()
        }
    }
    
    @IBInspectable var isSelected: Bool = true {
        didSet {
            setup()
        }
    }
    
    /// The view that shows the fill color
    private var fillView: UIView!
    
    /// Determines the whitespace between the border and the fill view
    private let inset: CGFloat = 4
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    override func prepareForInterfaceBuilder() {
        setup()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setup()
    }
    
    private func setup() {
        if fillView == nil {
            fillView = UIView()
            fillView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(fillView)
            addConstraints([
                NSLayoutConstraint(item: self, attribute: .top, relatedBy: .equal, toItem: fillView, attribute: .top, multiplier: 1, constant: -inset),
                NSLayoutConstraint(item: self, attribute: .trailing, relatedBy: .equal, toItem: fillView, attribute: .trailing, multiplier: 1, constant: inset),
                NSLayoutConstraint(item: self, attribute: .bottom, relatedBy: .equal, toItem: fillView, attribute: .bottom, multiplier: 1, constant: inset),
                NSLayoutConstraint(item: self, attribute: .leading, relatedBy: .equal, toItem: fillView, attribute: .leading, multiplier: 1, constant: -inset),
            ])
            updateConstraints()
        }
        
        layer.cornerRadius = bounds.height / 2
        layer.borderWidth = 1
        layer.borderColor = UIColor(hex: "#C7C7CC").cgColor
        fillView.backgroundColor = isSelected ? fillColor : .clear
        fillView.layer.cornerRadius = fillView.bounds.height / 2
    }
}

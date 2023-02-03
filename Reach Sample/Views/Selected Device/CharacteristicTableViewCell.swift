//
//  CharacteristicTableViewCell.swift
//  Reach Sample
//
//  Created by Cygnus on 1/14/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import UIKit

class CharacteristicTableViewCell: UITableViewCell {
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var valueLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    func animateColorFlash(_ color: UIColor) {
        let originalColor = self.backgroundColor ?? .clear
        self.animate(color: color) { _ in
            self.animate(color: originalColor)
        }
    }
    
    private func animate(color: UIColor, completion: ((Bool) -> Void)? = nil) {
        UIView.animate(withDuration: 0.5, delay: 0, options: .transitionCrossDissolve, animations: {
            self.backgroundColor = color
        }, completion: completion)
    }
}

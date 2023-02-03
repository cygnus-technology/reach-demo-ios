//
//  AvailableDeviceTableViewCell.swift
//  Reach Sample
//
//  Created by Cygnus on 1/13/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import UIKit
import CoreBluetooth

class AvailableDeviceTableViewCell: UITableViewCell {
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var iconView: UIImageView!
    @IBOutlet weak var idLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

    /// Sets the connection strength icon given a BluetoothDevice
    func setState(_ device: BluetoothDevice) {
        let name = device.name ?? "Unnamed"
        
        if let companyName = device.companyName {
            nameLabel.text = "\(name) - \(companyName)"
        } else {
            nameLabel.text = name
        }
        idLabel.text = device.uuid.uuidString
        
        switch device.rssiBucket {
        case 1:
            iconView.image = UIImage(named: "signal-low")
        case 2:
            iconView.image = UIImage(named: "signal-mid")
        case 3:
            iconView.image = UIImage(named: "signal-full")
        default:
            iconView.image = UIImage(named: "signal-empty")
        }
    }
}

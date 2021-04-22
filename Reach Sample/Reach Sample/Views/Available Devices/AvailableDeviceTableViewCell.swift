//
//  AvailableDeviceTableViewCell.swift
//  Reach Sample
//
//  Created by Cygnus on 3/8/21.
//  Copyright © 2021 Cygnus. All rights reserved.
//

import UIKit

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
        nameLabel.text = device.name ?? "Unnamed"
        idLabel.text = device.id.description
        
        let rssi = device.RSSI
        
        if rssi > -40 {
            iconView.image = #imageLiteral(resourceName: "Signal-three")
        } else if rssi > -60 {
            iconView.image = #imageLiteral(resourceName: "Signal-two")
        } else if rssi > -85 {
            iconView.image = #imageLiteral(resourceName: "Signal-one")
        } else {
            iconView.image = #imageLiteral(resourceName: "Signal-none")
        }
    }
}

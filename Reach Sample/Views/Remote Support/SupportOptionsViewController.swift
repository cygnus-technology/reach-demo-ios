//
//  SupportOptionsViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 6/20/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import UIKit

class SupportOptionsViewController: UIViewController {

    @IBOutlet weak var endSupportButton: UIButton!
    @IBOutlet weak var deviceButton: UIButton!
    
    var connectDevice: (() -> Void)!
    var disconnectDevice: (() -> Void)!
    var endSupport: (() -> Void)!
    var connectedDevice: BluetoothDevice? { SupportService.shared.selectedDevice }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        preferredContentSize = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let title = connectedDevice == nil ? "Connect to Device" : "Disconnect from Device"
        deviceButton.setTitle(title, for: .normal)
    }
    
    @IBAction func endSupportButtonTapped(_ sender: Any) {
        dismiss(animated: true)
        endSupport()
    }
    
    @IBAction func deviceButtonTapped(_ sender: Any) {
        dismiss(animated: true) { [self] in
            if connectedDevice == nil {
                connectDevice()
            } else {
                disconnectDevice()
            }
        }
    }
}

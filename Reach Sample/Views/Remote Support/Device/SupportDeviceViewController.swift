//
//  SupportDeviceViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 5/31/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import UIKit
import Combine

class SupportDeviceViewController: UIViewController, SupportTabViewController {
    
    @IBOutlet weak var inactiveView: UIView!
    @IBOutlet weak var logTextView: UITextView!
    @IBOutlet weak var deviceButton: PrimaryButton!
    
    var logger: TextViewLogger { SupportService.shared.logger }
    weak var connectedDevice: BluetoothDevice? { SupportService.shared.selectedDevice }
    private var bag = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        SupportService.shared.$selectedDevice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in self?.setupViews() }
            .store(in: &bag)
        
        logger.textView = logTextView
        setupViews()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let nav = segue.destination as? UINavigationController,
           let destination = nav.topViewController as? AvailableDevicesViewController
        {
            destination.supportSessionConnect = true
        } else if let destination = segue.destination as? SelectedDeviceViewController {
            destination.supportSessionParameters = true
            destination.connectedDevice = connectedDevice
        }
    }
    
    @IBAction func deviceButtonTapped(_ sender: Any) {
        if connectedDevice != nil {
            performSegue(withIdentifier: "deviceParameters", sender: self)
        } else {
            performSegue(withIdentifier: "connectDevice", sender: self)
        }
    }
    
    private func setupViews() {
        inactiveView.isHidden = connectedDevice != nil
        logTextView.isHidden = connectedDevice == nil
        let title = connectedDevice == nil ? "CONNECT TO A DEVICE" : "VIEW DEVICE PARAMETERS"
        deviceButton.setTitle(title, for: .normal)
    }
}

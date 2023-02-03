//
//  MainViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 11/17/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import UIKit
import Combine

/// View controller that embeds the app's main navigation controller and displays a status view when a session is active
class MainViewController: UIViewController {
    
    @IBOutlet weak var sessionView: UIView!
    @IBOutlet weak var deviceStatusIndicator: ConnectionStatusIndicator!
    @IBOutlet weak var deviceStatusLabel: UILabel!
    
    private var bag = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        SupportService.shared.$remoteSupport
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rs in
                self?.sessionView.isHidden = rs == nil
            }
            .store(in: &bag)
        
        SupportService.shared.$deviceStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.setDeviceStatus(status) }
            .store(in: &bag)
    }
    
    @IBAction func sessionViewTapped(_ sender: Any) {
        performSegue(withIdentifier: "showSession", sender: self)
    }
    
    private func setDeviceStatus(_ status: ConnectionStatus) {
        let device = SupportService.shared.selectedDevice
        var statusString = ""
        switch status {
        case .connected:
            statusString = device?.name ?? "Unnamed"
        case .reconnecting:
            statusString = "Reconnecting to \(device?.name ?? "Unnamed")"
        case .disconnected:
            statusString = "No Device Connected"
        }
        
        deviceStatusIndicator?.setStatus(to: status)
        deviceStatusLabel?.text = statusString
    }
}

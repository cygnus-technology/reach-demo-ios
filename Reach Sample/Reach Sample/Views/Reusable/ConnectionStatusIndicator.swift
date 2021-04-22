//
//  StatusIndicator.swift
//  Reach Sample
//
//  Created by Cygnus on 3/8/21.
//  Copyright © 2021 Cygnus. All rights reserved.
//

import UIKit

enum ConnectionStatus: String {
    case connected = "connected"
    case disconnected = "disconnected"
    case reconnecting = "reconnecting"
    
    var color: UIColor {
        switch self {
        case .connected:
            return UIColor(red:0.30, green:0.85, blue:0.39, alpha:1.0)
        case .reconnecting:
            return UIColor(red:1.00, green:0.80, blue:0.00, alpha:1.0)
        case .disconnected:
            return UIColor(red:1.00, green:0.23, blue:0.19, alpha:1.0)
        }
    }
}

class ConnectionStatusIndicator: UIView {
    var connectionStatus = ConnectionStatus.connected
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.layer.cornerRadius = self.bounds.height / 2
        self.setStatus(to: .connected)
    }
    
    func setStatus(to status: ConnectionStatus) {
        self.connectionStatus = status
        self.backgroundColor = self.connectionStatus.color
    }
}

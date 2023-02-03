//
//  BluetoothEncoding.swift
//  Reach Sample
//
//  Created by Cygnus on 6/22/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import Foundation

enum BluetoothEncoding: String, Codable {
    case utf8 = "utf-8"
    case hex = "hex"
    
    func encodeText(_ text: String) -> Data? {
        switch self {
        case .utf8:
            return text.data(using: .utf8)
        case .hex:
            return text.data(using: .hex)
        }
    }
}

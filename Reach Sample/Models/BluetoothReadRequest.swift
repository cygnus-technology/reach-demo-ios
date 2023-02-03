//
//  BluetoothReadRequest.swift
//  Reach Sample
//
//  Created by Cygnus on 6/22/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import Foundation

struct BluetoothReadRequest: Codable {
    let uuid: String
}

struct BluetoothReadResponse: Codable {
    let value: String
    let encoding: BluetoothEncoding
}

//
//  BluetoothWriteRequest.swift
//  Reach Sample
//
//  Created by Cygnus on 6/22/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import Foundation

struct BluetoothWriteRequest: Codable {
    let uuid: String
    let encoding: BluetoothEncoding
    let value: String
}

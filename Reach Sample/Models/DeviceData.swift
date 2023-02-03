//
//  DeviceData.swift
//  Reach Sample
//
//  Created by Cygnus on 6/22/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import Foundation

struct DeviceData: Codable {
    let localName: String
    let macAddress: String
    let rssi: Int
    let signalStrength: Int
    let advertisementData: [String : String]
    let services: [ServiceInfo]
}

struct DeviceList: Codable {
    let devices: [DeviceData]
}

struct ServiceInfo: Codable {
    let uuid: String
    let characteristics: [CharacteristicInfo]
}

struct CharacteristicInfo: Codable {
    let uuid: String
    let read: Bool
    let write: Bool
    let notify: Bool
    let name: String?
    let value: String?
    let encoding: BluetoothEncoding?
}

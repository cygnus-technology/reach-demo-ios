//
//  DeviceService.swift
//  IoT Platform Sample iOS App
//
//  Created by Conner Christianson on 6/21/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import Foundation
import BleLibrary

class DeviceService {
    
    static let shared = DeviceService()
    
    private(set) var knownCompanyIds = [Int : String]()
    
    @Published
    var selectedDevice: Device?
    
    private init() {
        guard let url = Bundle.main.url(forResource: "company_ids", withExtension: "json")
        else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let ids = try decoder.decode([KnownCompanyId].self, from: data)
            ids.forEach {
                knownCompanyIds[$0.code] = $0.name
            }
        } catch {
            print("Could not load company ID list: \(error)")
        }
    }
}

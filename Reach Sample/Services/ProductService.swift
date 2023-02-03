//
//  ProductService.swift
//  Reach Sample
//
//  Created by Cygnus on 12/15/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import Foundation
import PromiseKit
import RemoteSupport

class ProductService {
    
    static let shared = ProductService()
    
    private let queue = DispatchQueue.global(qos: .userInitiated)
    private let remoteSupportQueue = DispatchQueue(label: "remoteSupportService", qos: .userInteractive)
    private var remoteSupportPin: String?
    
    // FIXME: Add in your API key
    let apiKey = ""
    
    private init() {}
    
    func setRemoteSupportPin(_ client: String?) {
        remoteSupportQueue.async {
            self.remoteSupportPin = client
        }
    }
}

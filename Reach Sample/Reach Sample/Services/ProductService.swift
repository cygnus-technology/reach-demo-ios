//
//  ProductService.swift
//  Reach Sample
//
//  Created by Cygnus on 3/8/21.
//

import Foundation
import PromiseKit
import RemoteSupport

class ProductService {
    
    static let shared = ProductService()
    
    private let queue = DispatchQueue.global(qos: .userInitiated)
    private let remoteSupportQueue = DispatchQueue(label: "remoteSupportService", qos: .userInteractive)
    private var remoteSupportPin: String?
    
    private init() {}
    
    func setRemoteSupportPin(_ client: String?) {
        remoteSupportQueue.async {
            self.remoteSupportPin = client
        }
    }
}


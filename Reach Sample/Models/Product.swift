//
//  Product.swift
//  Reach Sample
//
//  Created by Cygnus on 12/15/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import Foundation

struct Product: Codable {
    var name: String
    var key: String
    var enabled: Bool
    var organizationId: String?
    var awsId: String?
}

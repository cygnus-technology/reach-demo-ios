//
//  User.swift
//  Reach Sample
//
//  Created by Cygnus on 12/15/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import Foundation

struct User: Codable {
    var firstName: String
    var lastName: String
    var userId: Int
    var email: String
    var role: Role
    
    enum Role: String, Codable {
        case owner = "OWNER"
    }
}

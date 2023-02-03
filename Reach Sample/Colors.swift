//
//  Colors.swift
//  Reach Sample
//
//  Created by Cygnus on 6/13/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import UIKit

enum Colors {
    case accent
    case background
    case border
    case gray
    case grayText
    case green
    case primary
    case primaryText
    case raisedBackground
    case red
    
    var color: UIColor {
        switch self {
        case .accent:
            return UIColor(named: "Accent")!
        case .background:
            return UIColor(named: "Background")!
        case .border:
            return UIColor(named: "Border")!
        case .gray:
            return UIColor(named: "Gray")!
        case .grayText:
            return UIColor(named: "Gray Text")!
        case .green:
            return UIColor(named: "Green")!
        case .primary:
            return UIColor(named: "Primary")!
        case .primaryText:
            return UIColor(named: "Primary Text")!
        case .raisedBackground:
            return UIColor(named: "Raised Background")!
        case .red:
            return UIColor(named: "Red")!
        }
    }
}

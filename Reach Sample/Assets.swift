//
//  Assets.swift
//  Reach Sample
//
//  Created by Cygnus on 6/20/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import UIKit

enum Assets {
    case screenShare
    case screenShareActive
    case screenShareDisabled
    case video
    case videoActive
    case videoDisabled
    
    var image: UIImage {
        switch self {
        case .screenShare:
            return UIImage(named: "screen-share")!
        case .screenShareActive:
            return UIImage(named: "screen-share-active")!
        case .screenShareDisabled:
            return UIImage(named: "screen-share-disabled")!
        case .video:
            return UIImage(named: "video")!
        case .videoActive:
            return UIImage(named: "video-active")!
        case .videoDisabled:
            return UIImage(named: "video-disabled")!
        }
    }
}

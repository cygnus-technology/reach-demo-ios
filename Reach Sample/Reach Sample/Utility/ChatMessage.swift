//
//  ChatMessage.swift
//  Reach Sample
//
//  Created by Cygnus on 3/8/21.
//  Copyright © 2021 Cygnus. All rights reserved.
//

import UIKit
import AVKit

/// Applies to both sent and received messages. As of now, only one of the `message`, `image`, and `videoUrl` variables will have a value
class ChatMessage {
    var id: Int
    
    /// True if it's a sent message, false if received
    var sent: Bool
    
    /// Used for loading UI when we receive a partial message, ie. the first chunk of a large video
    var loading: Bool = false
    
    /// Text message
    var message: String?
    
    /// Image message
    var image: UIImage?
    
    /// Video message
    var player: AVPlayer?
    
    init(id: Int = -1, sent: Bool, loading: Bool = false, message: String? = nil, image: UIImage? = nil, player: AVPlayer? = nil) {
       self.id = id
       self.sent = sent
       self.loading = loading
       self.message = message
       self.image = image
       self.player = player
   }
}

enum MessageCategory: UInt16 {
    case deviceData = 110
    case bluetoothReadRequest
    case bluetoothWriteRequest
    case diagnosticHeartbeat
    case image
    case video
    case bluetoothNotifyRequest
    case multipartText = 200
    
    var isDisplayableMessage: Bool {
        return self == .image || self == .video || self == .multipartText
    }
}

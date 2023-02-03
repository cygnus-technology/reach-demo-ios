//
//  ChatMessage.swift
//  Reach Sample
//
//  Created by Cygnus on 1/14/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import UIKit
import AVKit
import RemoteSupport

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
    case bluetoothReadRequest = 111
    case bluetoothWriteRequest = 112
    case diagnosticHeartbeat = 113
    case image = 114
    case video = 115
    case bluetoothNotifyRequest = 116
    case requestDeviceList = 117
    case connectToDevice = 118
    case disconnectFromDevice = 119
    case startSharing = 120
    case stopSharing = 121
    case multipartText = 200
    
    var isDisplayableMessage: Bool {
        return self == .image || self == .video || self == .multipartText
    }
}

enum MediaSharingType: Int32 {
    case video
    case screen
}

enum MessageErrors: String, RSErrorResponse {
    case invalidState = "Invalid application state"
    case deviceConnectionError = "Device connection error"
    case mediaShareError = "Error initiating media sharing"
    case jsonParseError = "Unable to parse json message"
    case userTimeout = "User has not responded to request"
    
    var message: String {
        return rawValue
    }
    
    var statusCode: UInt32 {
        switch self {
        case .invalidState:
            return 1
        case .deviceConnectionError:
            return 2
        case .mediaShareError:
            return 3
        case .jsonParseError:
            return 4
        case .userTimeout:
            return 5
        }
    }
}

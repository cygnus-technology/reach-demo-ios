//
//  SupportService.swift
//  Reach Sample
//
//  Created by Cygnus on 11/8/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import Foundation
import RemoteSupport
import CoreBluetooth
import Combine
import PromiseKit
import AVFoundation

class SupportService {
    
    static let shared = SupportService()
    
    /// Event fired when the peer has ended the session
    let onSessionEnded: AnyPublisher<Void, Never>
    private let onSessionEndedSubject = PassthroughSubject<Void, Never>()
    
    /// Event fired when a message is received
    let onMessage: AnyPublisher<ChatMessage, Never>
    private let onMessageSubject = PassthroughSubject<ChatMessage, Never>()
    
    /// Event fired when a partial message cannot be fully delivered
    let onMessageError: AnyPublisher<Int, Never>
    private let onMessageErrorSubject = PassthroughSubject<Int, Never>()
    
    /// Event fired when a full message is received that existed as a partial message
    let onReloadMessage: AnyPublisher<ChatMessage, Never>
    private let onReloadMessageSubject = PassthroughSubject<ChatMessage, Never>()
    
    @Published
    var isVideoShareOn = false
    
    @Published
    var isScreenShareOn = false
    
    @Published
    private (set) var messages = [ChatMessage]()
    
    @Published
    private (set) var deviceStatus: ConnectionStatus = .disconnected
    
    @Published
    private (set) var remoteSupport: RemoteSupportClient?
    
    @Published
    var selectedDevice: BluetoothDevice? {
        didSet {
            oldValue?.unsubscribeFromPeripheralUpdates(self)
            selectedDevice?.subscribeToPeripheralUpdates(self)
            if selectedDevice?.isConnected == true {
                deviceStatus = .connected
            } else if selectedDevice != nil {
                deviceStatus = .reconnecting
            } else {
                deviceStatus = .disconnected
            }
        }
    }
    
    var isConnected: Bool {
        remoteSupport?.isConnected == true
    }
    
    /// Whether there is a remote support session currently active, regardless if the connection is open or not
    var sessionActive: Bool {
        remoteSupport != nil
    }
    
    private (set) var logger = TextViewLogger()
    private (set) var videoController: CameraStreamController?
    private (set) var screenController: ScreenCaptureController?
    private (set) var isCameraFrontFacing = false
    private (set) var knownCompanyIds = [Int : String]()
    var bluetoothStateDelegateId: String = "SupportService"
    var peripheralDelegateId: String = "SupportService"
    
    private var bag = Set<AnyCancellable>()
    private var heartbeatTimer: Timer?
    
    private init() {
        onSessionEnded = onSessionEndedSubject.eraseToAnyPublisher()
        onMessage = onMessageSubject.eraseToAnyPublisher()
        onMessageError = onMessageErrorSubject.eraseToAnyPublisher()
        onReloadMessage = onReloadMessageSubject.eraseToAnyPublisher()
        
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
    
    func connectToSession(pin: String, apiKey: String) -> Promise<Void> {
        let rs = setupSession(apiKey: apiKey)
        let promise = rs.connectToSupportSession(pin: pin)
        promise.catch { error in
            self.remoteSupport = nil
        }
        return promise
    }
    
    func hostSession(apiKey: String) -> Promise<String> {
        let rs = setupSession(apiKey: apiKey)
        let promise = rs.initiateSupportSession()
        promise.catch { error in
            self.remoteSupport = nil
        }
        return promise
    }
    
    func endSession() {
        remoteSupport?.disconnect()
        tearDown()
    }
    
    func tearDown() {
        remoteSupport = nil
        isVideoShareOn = false
        isScreenShareOn = false
        heartbeatTimer?.invalidate()
        disconnectDevice()
        messages.removeAll()
        bag.removeAll()
    }
    
    /// Disconnects from selected device and sends a notification to the connected peer if a session is active
    func disconnectDevice() {
        selectedDevice?.unsubscribeFromPeripheralUpdates(self)
        selectedDevice?.disconnect()
        selectedDevice = nil
        
        let notification = RSNotification(category: MessageCategory.disconnectFromDevice.rawValue, data: WellKnownTagEncoder.Empty)
        remoteSupport?.sendNotification(notification: notification).catch { error in
            print(error)
        }
    }
    
    private func setupSession(apiKey: String) -> RemoteSupportClient {
        let rs = RemoteSupportClient(
            apiUrlBase: Config.url,
            apiKey: apiKey,
            retainLogs: true,
            timeout: 5,
            logger: logger
        )
        
        rs.onConnect
            .receive(on: DispatchQueue.main)
            .sink { self.handleConnect() }
            .store(in: &bag)
        
        rs.onDisconnect
            .receive(on: DispatchQueue.main)
            .sink { args in self.handleDisconnect(args) }
            .store(in: &bag)
        
        rs.onPartialMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] args in self?.handlePartialMessage(args) }
            .store(in: &bag)
        
        rs.onMessageError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] args in self?.handleMessageError(args) }
            .store(in: &bag)
        
        rs.onNotification
            .receive(on: DispatchQueue.main)
            .sink { [weak self] args in self?.handleNotification(args) }
            .store(in: &bag)
        
        rs.onCommand
            .receive(on: DispatchQueue.main)
            .sink { args in self.handleCommand(args) }
            .store(in: &bag)
        
        rs.onQuery
            .receive(on: DispatchQueue.main)
            .sink { args in self.handleQuery(args) }
            .store(in: &bag)
        
        rs.onVideoCapture
            .receive(on: DispatchQueue.main)
            .sink { args in self.handleVideoCapture(args) }
            .store(in: &bag)
        
        rs.onVideoCaptureFailed
            .receive(on: DispatchQueue.main)
            .sink { error in self.handleVideoCaptureError(error) }
            .store(in: &bag)
        
        rs.onScreenCapture
            .receive(on: DispatchQueue.main)
            .sink { args in self.handleScreenCapture(args) }
            .store(in: &bag)
        
        rs.onScreenCaptureFailed
            .receive(on: DispatchQueue.main)
            .sink { error in self.handleScreenCaptureError(error) }
            .store(in: &bag)
        
        remoteSupport = rs
        return rs
    }
    
    private func setupHeartbeatTimer() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
            guard SupportService.shared.isConnected,
                  let rssi = SupportService.shared.selectedDevice?.rssi
            else { return }
            
            let status = SupportService.shared.deviceStatus.rawValue
            let json: [String : Any] = [
                "rssi": rssi,
                "status": status
            ]
            
            do {
                let data = try JSONSerialization.data(withJSONObject: json)
                self?.remoteSupport?.sendNotification(notification: RSNotification(category: MessageCategory.diagnosticHeartbeat.rawValue, data: RSTaggedData(tag: DefaultTag.Object, data: data))).catch { error in print(error) }
            } catch {
                print(error)
            }
        }
    }
    
    private func sendDeviceData() {
        guard isConnected,
              let connectedDevice = selectedDevice
        else { return }
        
        do {
            let deviceData = connectedDevice.getDeviceData()
            let tagged = try WellKnownTagEncoder.Json.encode(deviceData)
            let notification = RSNotification(category: MessageCategory.deviceData.rawValue, data: tagged)
            remoteSupport?.sendNotification(notification: notification)
                .catch { error in
                    print("Error sending device data: \(error.localizedDescription)")
                }
        } catch {
            print(error)
        }
    }
}

// MARK: - Video
extension SupportService {
    
    func startVideoStream() -> Bool {
        guard let rs = remoteSupport,
              let configuration = configuration(isFrontFacing: isCameraFrontFacing)
        else { return false }
        return rs.addVideoStream(configuration)
    }
    
    func stopVideoStream() {
        videoController?.stop()
        isCameraFrontFacing = false
        isVideoShareOn = false
    }
    
    func flipCamera() -> Promise<Void> {
        
        guard let configuration = configuration(isFrontFacing: !isCameraFrontFacing)
        else { return Promise(error: ErrorResponse(message: "Could not get new camera configuration")) }
        
        return videoController?.switchCamera(configuration).done {
            self.isCameraFrontFacing.toggle()
        } ?? Promise(error: ErrorResponse(message: "Could not access video controller"))
    }
    
    private func configuration(isFrontFacing: Bool) -> CameraFormat? {
        let fullHd = 1920 * 1080
        let cameras = CameraInfo.getCameras()
        guard let camera = cameras.first(where: { $0.isFrontFacing == isFrontFacing }),
              let format = camera.formats.filter({ $0.frameSize.size <= fullHd }).max(by: { $0.frameSize.size <= $1.frameSize.size })
        else { return nil }
        return camera.withFormat(format: format)
    }
}

// MARK: - Screen
extension SupportService {
    
    func startScreenShare() -> Bool {
        guard let rs = remoteSupport else { return false }
        return rs.addScreenSharing(configuration())
    }
    
    func stopScreenShare() {
        screenController?.stop()
        isScreenShareOn = false
    }
    
    private func configuration() -> ScreenFormat {
        let frameSize = FrameSize(
            width: Int(UIScreen.main.bounds.width),
            height: Int(UIScreen.main.bounds.height)
        )
        let screenFormat = ScreenFormat(format: frameSize)
        return screenFormat
    }
}

// MARK: - Chat
extension SupportService {
    
    func sendMessage(_ message: String) -> Promise<Void> {
        guard let rs = remoteSupport else {
            return Promise(error: ErrorResponse(message: "Remote support session is not active"))
        }
        
        return rs.sendChat(text: message).done {
            let message = ChatMessage(sent: true, message: message)
            self.messages.append(message)
            self.onMessageSubject.send(message)
        }
    }
    
    func sendImage(_ image: UIImage) -> Promise<Void> {
        guard let rs = remoteSupport else {
            return Promise(error: ErrorResponse(message: "Remote support session is not active"))
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.1) else {
            return Promise(error: ErrorResponse(message: "Could not compress image"))
        }
        
        return rs.sendBytes(
            data: imageData,
            tag: "image/jpeg",
            category: MessageCategory.image.rawValue
        ).done {
            let message = ChatMessage(sent: true, image: image)
            self.messages.append(message)
            self.onMessageSubject.send(message)
        }
    }
    
    func sendVideo(_ url: URL) -> Promise<Void> {
        guard let rs = remoteSupport else {
            return Promise(error: ErrorResponse(message: "Remote support session is not active"))
        }
        
        guard let data = try? Data(contentsOf: url) else {
            return Promise(error: ErrorResponse(message: "Could not access contents of video URL"))
        }
        
        return rs.sendBytes(
            data: data,
            tag: "video/mp4",
            category: MessageCategory.video.rawValue
        ).done {
            let player = AVPlayer(url: url)
            let message = ChatMessage(sent: true, player: player)
            self.messages.append(message)
            self.onMessageSubject.send(message)
        }
    }
    
    func clearMessages() {
        messages.removeAll()
    }
}

// MARK: - Remote Support Delegate
extension SupportService {
    
    private func handleConnect() {
        sendDeviceData()
        setupHeartbeatTimer()
        heartbeatTimer?.fire()
    }
    
    private func handleDisconnect(_ args: DisconnectEventArgs) {
        if args.expected {
            let alert = UIAlertController(title: nil, message: "Representative has disconnected from support session", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Ok", style: .default) { action in
                self.selectedDevice?.unsubscribeFromPeripheralUpdates(self)
                self.tearDown()
                self.onSessionEndedSubject.send(())
            })
            UIAlertController.showAlert(alert)
        }
    }
    
    private func handlePartialMessage(_ args: PartialMessageReceivedEventArgs) {
        guard !messages.contains(where: { $0.id == args.id }) else { return }

        let message: ChatMessage
        switch args.category {
        case DefaultCategory.Chat:
            message = ChatMessage(id: Int(args.id), sent: false, loading: true, message: "")
        case MessageCategory.image.rawValue:
            message = ChatMessage(id: Int(args.id), sent: false, loading: true, image: UIImage())
        case MessageCategory.video.rawValue:
            message = ChatMessage(id: Int(args.id), sent: false, loading: true)
        default:
            return
        }
        
        messages.append(message)
        onMessageSubject.send(message)
    }
    
    private func handleMessageError(_ args: MessageErrorEventArgs) {
        messages.removeAll { $0.id == args.messageId }
        onMessageErrorSubject.send(Int(args.messageId))
    }
    
    private func handleNotification(_ args: NotificationEventArgs) {
        func showMessage(_ message: ChatMessage, reload: Bool) {
            if reload {
                onReloadMessageSubject.send(message)
            } else {
                messages.append(message)
                onMessageSubject.send(message)
            }
        }
        
        var message = messages.first { $0.id == args.notification.id }
        let exists = message != nil
        if message == nil {
            message = ChatMessage(id: Int(args.notification.id), sent: false)
        }
        message!.loading = false
        
        switch args.notification.category {
        case DefaultCategory.Chat:
            let messageData = Data(args.notification.data.data)
            message!.message = String(data: messageData, encoding: .utf8)
            
        case MessageCategory.image.rawValue:
            message!.image = UIImage(data: Data(args.notification.data.data))
            
        case MessageCategory.video.rawValue:
            print("Received video, attempting to write to file")
            
            let file = "remote-support-\(Int(Date().timeIntervalSince1970 * 1000))"
            Data(args.notification.data.data).writeMp4DataToLocalUrl(with: file).done(on: DispatchQueue.global(qos: .userInitiated)) { url in
                let player = AVPlayer(url: url)
                message!.player = player
            }.done {
                showMessage(message!, reload: exists)
            }.catch { error in
                print(error)
            }
            
            return
            
        default:
            return
        }
        
        showMessage(message!, reload: exists)
    }
    
    private func handleCommand(_ args: CommandEventArgs) {
        switch args.command.category {
        case MessageCategory.bluetoothWriteRequest.rawValue:
            handleWriteRequest(command: args.command, context: args.context)
        case MessageCategory.bluetoothNotifyRequest.rawValue:
            handleNotifyRequest(command: args.command, context: args.context)
        case MessageCategory.connectToDevice.rawValue:
            handleConnectRequest(command: args.command, context: args.context)
        case MessageCategory.disconnectFromDevice.rawValue:
            handleDisconnectRequest(command: args.command, context: args.context)
        case MessageCategory.startSharing.rawValue, MessageCategory.stopSharing.rawValue:
            guard let raw = WellKnownTagEncoder.Number.decode(type: Int32.self, args.command.data),
                  let mediaType = MediaSharingType(rawValue: raw)
            else {
                args.context.error(MessageErrors.mediaShareError)
                return
            }
            
            switch mediaType {
            case .video:
                handleVideoRequest(command: args.command, context: args.context)
            case .screen:
                handleScreenRequest(command: args.command, context: args.context)
            }
        default:
            if MessageCategory(rawValue: args.command.category) == nil {
                let error = RSError(message: "Received unknown command", statusCode: 500)
                logger.error(error.message)
                args.context.error(error)
            }
        }
    }
    
    private func handleQuery(_ args: QueryEventArgs) {
        switch args.query.category {
        case MessageCategory.bluetoothReadRequest.rawValue:
            handleReadRequest(query: args.query, context: args.context)
        case MessageCategory.requestDeviceList.rawValue:
            handleDevicesRequest(query: args.query, context: args.context)
        default:
            if MessageCategory(rawValue: args.query.category) == nil {
                let error = RSError(message: "Received unknown query", statusCode: 500)
                logger.error(error.message)
                args.context.error(error)
            }
        }
    }
    
    private func handleVideoCapture(_ args: VideoCaptureEventArgs) {
        videoController = args.controller
        isVideoShareOn = true
    }
    
    private func handleVideoCaptureError(_ error: Error) {
        videoController = nil
    }
    
    private func handleScreenCapture(_ args: ScreenCaptureEventArgs) {
        screenController = args.controller
        isScreenShareOn = true
    }
    
    private func handleScreenCaptureError(_ error: Error) {
        screenController = nil
    }
}

// MARK: - Command Handlers
extension SupportService {
    
    private func handleWriteRequest(command: RSCommand, context: RSCommandContext) {
        if selectedDevice?.isConnected == true,
           let request: BluetoothWriteRequest = try? WellKnownTagEncoder.Json.decode(command.data),
           let characteristic = selectedDevice?.getCharacteristic(uuid: request.uuid),
           let data = request.encoding.encodeText(request.value)
        {
            selectedDevice?.writeValue(data, characteristic: characteristic).done {
                context.complete()
            }.catch { err in
                let error = RSError(message: err.localizedDescription, statusCode: 500)
                self.logger.error(err.localizedDescription)
                context.error(error)
            }
        } else {
            let errorText = (selectedDevice?.isConnected ?? false) ? "Unknown characteristic" : "Not connected to device"
            self.logger.error(errorText)
            context.error(RSError(message: errorText, statusCode: 500))
        }
    }
    
    private func handleNotifyRequest(command: RSCommand, context: RSCommandContext) {
        if selectedDevice?.isConnected == true,
           let request: BluetoothNotifyRequest = try? WellKnownTagEncoder.Json.decode(command.data),
           let characteristic = selectedDevice?.getCharacteristic(uuid: request.uuid)
        {
            selectedDevice?.setNotify(characteristic: characteristic, notify: request.setNotify).done {
                context.complete()
            }.catch { err in
                let error = RSError(message: err.localizedDescription, statusCode: 500)
                context.error(error)
            }
        }
    }
    
    private func handleConnectRequest(command: RSCommand, context: RSCommandContext) {
        let alert = UIAlertController(title: nil, message: "Agent is requesting to use Bluetooth to connect to a device.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Deny", style: .cancel) { action in
            context.error(MessageErrors.deviceConnectionError)
        })
        alert.addAction(UIAlertAction(title: "Allow", style: .default) { action in
            guard let request: BluetoothConnectRequest = try? WellKnownTagEncoder.Json.decode(command.data) else {
                context.error(MessageErrors.jsonParseError)
                return
            }
            guard let device = BluetoothManager.shared.scannedDevices.first(where: { $0.uuid == UUID(uuidString: request.macAddress) }) else {
                context.error(RSError(message: "Unable to select device", statusCode: MessageErrors.deviceConnectionError.statusCode))
                return
            }
            
            device.connect().done {
                self.selectedDevice = device
                context.complete()
            }.catch { error in
                context.error(RSError(message: error.localizedDescription, statusCode: MessageErrors.deviceConnectionError.statusCode))
            }
        })
        
        UIAlertController.showAlert(alert)
    }
    
    private func handleDisconnectRequest(command: RSCommand, context: RSCommandContext) {
        guard let device = selectedDevice else {
            context.error(RSError(message: "No connected device to disconnect"))
            return
        }
        
        selectedDevice = nil
        device.unsubscribeFromPeripheralUpdates(self)
        device.disconnect()
        context.complete()
    }
    
    private func handleVideoRequest(command: RSCommand, context: RSCommandContext) {
        if command.category == MessageCategory.startSharing.rawValue {
            let alert = UIAlertController(title: nil, message: "Agent is requesting you to share your video.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "DENY", style: .cancel) { action in
                context.error(MessageErrors.mediaShareError)
            })
            alert.addAction(UIAlertAction(title: "ALLOW", style: .default) { action in
                if let controller = self.videoController {
                    controller.start().done {
                        self.isVideoShareOn = true
                        context.complete()
                    }.catch { error in
                        self.handleVideoCaptureError(error)
                        context.error(MessageErrors.mediaShareError)
                    }
                } else if self.startVideoStream() {
                    context.complete()
                } else {
                    context.error(MessageErrors.mediaShareError)
                }
            })
            UIAlertController.showAlert(alert)
        } else {
            stopVideoStream()
            isVideoShareOn = false
            context.complete()
        }
    }
    
    private func handleScreenRequest(command: RSCommand, context: RSCommandContext) {
        if command.category == MessageCategory.startSharing.rawValue {
            let alert = UIAlertController(title: nil, message: "Agent is requesting you to share your screen.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "DENY", style: .cancel) { action in
                context.error(MessageErrors.mediaShareError)
            })
            alert.addAction(UIAlertAction(title: "ALLOW", style: .default) { action in
                if let controller = self.screenController {
                    controller.start().done {
                        self.isScreenShareOn = true
                        self.handleScreenCapture(ScreenCaptureEventArgs(controller: controller))
                        context.complete()
                    }.catch { error in
                        self.handleScreenCaptureError(error)
                        context.error(MessageErrors.mediaShareError)
                    }
                } else if self.startScreenShare() {
                    context.complete()
                } else {
                    context.error(MessageErrors.mediaShareError)
                }
            })
            UIAlertController.showAlert(alert)
        } else {
            stopScreenShare()
            isScreenShareOn = false
            context.complete()
        }
    }
}

// MARK: - Query Handlers
extension SupportService {
    
    private func handleReadRequest(query: RSQuery, context: RSQueryContext) {
        let device = SupportService.shared.selectedDevice
        if device?.isConnected == true,
           let request: BluetoothReadRequest = try? WellKnownTagEncoder.Json.decode(query.data),
           let characteristic = device?.getCharacteristic(uuid: request.uuid)
        {
            device?.readValue(from: characteristic).done { value in
                let tagged = WellKnownTagEncoder.Bytes.encode(value)
                context.respond(tagged, isLastMessage: true)
            }.catch { err in
                let error = RSError(message: "Failed to read value from characteristic", statusCode: 500)
                self.logger.error(err.localizedDescription)
                context.error(error)
            }
        } else {
            let errorText = (device?.isConnected ?? false) ? "Unknown characteristic" : "Not connected to device"
            logger.error(errorText)
            context.error(RSError(message: errorText, statusCode: 500))
        }
    }
    
    private func handleDevicesRequest(query: RSQuery, context: RSQueryContext) {
        BluetoothManager.shared.startScanning().then {
            after(seconds: 3)
        }.done {
            let devices = DeviceList(
                devices: BluetoothManager.shared.scannedDevices
                    .filter{ $0.isValid }
                    .sorted {
                        if $0.rssiBucket == $1.rssiBucket {
                            if $0.name == $1.name {
                                return $0.rssi > $1.rssi
                            }
                            return $0.name ?? "ZZZZ" < $1.name ?? "ZZZZ"
                        }
                        return $0.rssiBucket > $1.rssiBucket
                        
                    }
                    .map {
                        $0.getDeviceData()
                    }
                
            )
            let tagged = try WellKnownTagEncoder.Json.encode(devices)
            BluetoothManager.shared.stopScanning()
            context.respond(tagged, isLastMessage: true)
        }.catch { error in
            context.error(RSError(message: error.localizedDescription))
        }
    }
}

extension SupportService: BluetoothStateDelegate {
    
    func didScanAdvertisedData(for device: BluetoothDevice) {
        
    }
    
    func didConnectToDevice(_ device: BluetoothDevice) {
        DispatchQueue.main.async {
            self.deviceStatus = .connected
            self.heartbeatTimer?.fire()
        }
    }
    
    func failedToConnectToDevice(_ device: BluetoothDevice) {
        
    }
    
    func didDisconnectFromDevice(_ device: BluetoothDevice) {
        DispatchQueue.main.async {
            self.deviceStatus = self.selectedDevice == nil ? .disconnected : .reconnecting
            self.heartbeatTimer?.fire()
            self.selectedDevice?.connect().catch { error in
                self.deviceStatus = .disconnected
                UIAlertController.showAlert(title: "Device Disconnected", message: "Please reconnect your device to your phone to continue troubleshooting.", buttonTitle: "Dismiss")
            }
        }
    }
    
    func bluetoothReset() {
        
    }
}

// MARK: - Bluetooth Delegate
extension SupportService: PeripheralDelegate {
    
    func didDiscoverCharacteristics(for peripheral: CBPeripheral, characteristics: [CBCharacteristic], service: CBService) {
        let device = SupportService.shared.selectedDevice
        service.characteristics?.forEach {
            device?.readValue(from: $0).cauterize()
        }
    }
    
    func didDiscoverServices(for peripheral: CBPeripheral, services: [CBService]) {
        sendDeviceData()
    }
    
    func didUpdateDescriptor(for peripheral: CBPeripheral, descriptor: CBDescriptor) {
        sendDeviceData()
    }
    
    func didUpdateCharacteristic(for peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        sendDeviceData()
    }
}

/// The format in which error messages are received via the server
struct ErrorResponse: Codable, LocalizedError {
    var message: String
    var statusCode: Int = -1
    
    var errorDescription: String? {
        return message
    }
    
    enum CodingKeys: String, CodingKey {
        case message
    }
}

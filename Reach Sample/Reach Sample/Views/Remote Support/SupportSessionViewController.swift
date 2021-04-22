//
//  SupportSessionViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 3/8/21.
//  Copyright © 2021 Cygnus. All rights reserved.
//

import UIKit
import CoreBluetooth
import RemoteSupport
import MobileCoreServices
import PromiseKit
import AVFoundation
import AVKit
import Photos

class SupportSessionViewController: UIViewController {
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var deviceStatusIndicator: ConnectionStatusIndicator!
    @IBOutlet weak var deviceStatusLabel: UILabel!
    @IBOutlet weak var supportStatusIndicator: ConnectionStatusIndicator!
    @IBOutlet weak var supportStatusLabel: UILabel!
    @IBOutlet weak var logTextView: UITextView!
    @IBOutlet weak var logContainerView: UIView!
    @IBOutlet weak var logHeightConstraint: NSLayoutConstraint?
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var noMessageStackView: UIStackView!
    
    @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var chatTextField: UITextField!
    @IBOutlet weak var sendActivityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var cameraButton: UIButton!
    
    @IBOutlet weak var mediaViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var mediaImageView: UIImageView!
    @IBOutlet weak var mediaImageViewWidth: NSLayoutConstraint!
    @IBOutlet weak var mediaViewSpacerHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var mediaImageViewHeightComparisonConstraint: NSLayoutConstraint!
    
    weak var remoteSupport: RemoteSupportClient?
    weak var connectedDevice: BluetoothDevice!
    weak var logger: TextViewLogger!
    var messages = [ChatMessage]()
    
    var deviceStatus: ConnectionStatus = .connected {
        didSet {
            DispatchQueue.main.async {
                var statusString = ""
                
                switch self.deviceStatus {
                case .connected:
                    statusString = "Connected to \(self.connectedDevice.name ?? "Unnamed")"
                case .reconnecting:
                    statusString = "Reconnecting to \(self.connectedDevice.name ?? "Unnamed")"
                case .disconnected:
                    statusString = "Disconnected"
                }
                
                self.deviceStatusIndicator.setStatus(to: self.deviceStatus)
                self.deviceStatusLabel.text = statusString
            }
        }
    }
    
    private var videoUrl: URL?
    private var shouldSendDiagnostics = true
    private var heartbeatTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        sendButton.setImage(#imageLiteral(resourceName: "send"), for: .disabled)
        sendButton.setImage(#imageLiteral(resourceName: "send-orange"), for: .normal)
        
        tableView.tableFooterView = UIView()
        tableView.estimatedRowHeight = 56
        
        logger.textView = logTextView
        remoteSupport?.delegate = self
        chatTextField.delegate = self
        
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        view.backgroundColor = .clear
        chatTextField.rightView = view
        chatTextField.rightViewMode = .always
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
            guard self?.remoteSupport?.isConnected == true, let rssi = self?.connectedDevice.RSSI, let status = self?.deviceStatus.rawValue else { return }
            
            let json: [String : Any] = [
                "rssi": Int(rssi),
                "status": status
            ]
            
            do {
                let data = try JSONSerialization.data(withJSONObject: json)
                self?.remoteSupport?.sendNotification(notification: RSNotification(category: MessageCategory.diagnosticHeartbeat.rawValue, data: RSTaggedData(tag: DefaultTag.Object, data: data))).catch { error in print(error) }
            } catch {
                print(error)
            }
        }
        
        if PHPhotoLibrary.authorizationStatus() == .notDetermined  {
            PHPhotoLibrary.requestAuthorization { status in }
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        messages.removeAll()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardNotification(notification:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        BluetoothManager.shared.subscribeToBluetoothState(self)
        connectedDevice.subscribeToPeripheralUpdates(self)
        
        // Set current statuses
        if remoteSupport?.isConnected ?? false {
            remoteSupportDidConnect()
        } else {
            remoteSupportWillResetConnection()
            supportStatusLabel.text = "Connecting with Agent..."
        }
        
        deviceStatus = connectedDevice.isConnected ? .connected : .reconnecting
        
        if !connectedDevice.isConnected {
            didDisconnectFromDevice(connectedDevice)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        NotificationCenter.default.removeObserver(self)
        BluetoothManager.shared.unsubscribeFromBluetoothState(self)
        connectedDevice.unsubscribeFromPeripheralUpdates(self)
    }
    
    @IBAction func disconnectButtonTapped(_ sender: Any) {
        let alert = UIAlertController(title: "Disconnect Confirmation", message: "Are you sure you wish to disconnect? This will end the session.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Disconnect", style: .destructive) { action in
            self.remoteSupport?.disconnect()
            self.heartbeatTimer?.invalidate()
            self.remoteSupport = nil
            self.connectedDevice.disconnect()
            self.dismiss(animated: true)
        })
        
        self.present(alert, animated: true)
    }
    
    @IBAction func sendButtonTapped(_ sender: Any) {
        guard let remoteSupport = self.remoteSupport else { return }
        
        self.chatTextField.resignFirstResponder()
        self.sendActivityIndicator.startAnimating()
        self.sendButton.isHidden = true
        var mediaPromise = Promise()
        var textPromise = Promise()
        
        if let image = self.mediaImageView.image, let imageData = image.jpegData(compressionQuality: 0.1) {
            print("Sending image")
            mediaPromise = remoteSupport.sendBytes(data: imageData, tag: "image/jpeg", category: 114).done { [weak self] in
                self?.messages.append(ChatMessage(sent: true, image: image))
                self?.cancelMedia()
                self?.showNewMessage(with: .right)
            }
        } else if let videoUrl = self.videoUrl {
            print("Sending video")
            mediaPromise = mediaPromise.map {
                try Data(contentsOf: videoUrl)
            }.then { videoData in
                remoteSupport.sendBytes(data: videoData, tag: "video/mp4", category: 115)
            }.done { [weak self] in
                let player = AVPlayer(url: videoUrl)
                self?.messages.append(ChatMessage(sent: true, player: player))
                self?.cancelMedia()
                self?.showNewMessage(with: .right)
            }
        }
        
        if let message = self.chatTextField.text, !message.isEmpty {
            let promise: Promise<Void>
            
            if message.lowercased() == "multi" {
                let query = RSQuery(category: 200, data: RSTaggedData(tag: DefaultTag.Chat, data: message.data(using: .utf8) ?? Data()))
                let receipt = remoteSupport.sendQuery(query: query, timeout: 10) { [weak self] data, isLastMessage in
                    DispatchQueue.main.async {
                        self?.messages.append(ChatMessage(sent: false, message: String(data: data.data, encoding: .utf8)))
                        self?.showNewMessage(with: .left)
                    }
                }
                
                promise = receipt.complete
            } else {
                promise = remoteSupport.sendChat(text: message)
            }
            
            messages.append(ChatMessage(sent: true, message: message))
            chatTextField.text = ""
            showNewMessage(with: .right)
            textPromise = mediaPromise.then { promise }
        }
        
        when(fulfilled: mediaPromise, textPromise).done { [weak self] in
            self?.sendButton.isEnabled = false
        }.catch { [weak self] error in
            let message = (error as? RSErrorResponse)?.message ?? error.localizedDescription
            self?.showAlert(title: "Error sending messages", message: message)
        }.finally { [weak self] in
            self?.sendButton.isHidden = false
            self?.sendActivityIndicator.stopAnimating()
        }
    }
    
    @IBAction func cameraButtonTapped(_ sender: Any) {
        let vc = UIImagePickerController()
        vc.allowsEditing = false
        vc.delegate = self
        vc.mediaTypes = [
            kUTTypeImage as String,
            kUTTypeVideo as String,
            kUTTypeMovie as String
        ]
        vc.videoExportPreset = AVAssetExportPresetMediumQuality
        
        let actionSheet = UIAlertController(title: nil, message: "Select Image Source", preferredStyle: .actionSheet)
        actionSheet.popoverPresentationController?.sourceView = self.cameraButton
        actionSheet.popoverPresentationController?.sourceRect = self.cameraButton.bounds
        actionSheet.addAction(UIAlertAction(title: "Camera", style: .default) { action in
            vc.sourceType = .camera
            self.present(vc, animated: true)
        })
        
        actionSheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { action in
            vc.sourceType = .photoLibrary
            self.present(vc, animated: true)
        })
        
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { action in })
        present(actionSheet, animated: true)
    }
    
    private func showNewMessage(with animation: UITableView.RowAnimation) {
        self.tableView.isHidden = false
        self.noMessageStackView.isHidden = true
        
        let indexPaths = [IndexPath(row: self.messages.count - 1, section: 0)]
        self.tableView.insertRows(at: indexPaths, with: animation)
        self.tableView.scrollToRow(at: indexPaths.first!, at: .bottom, animated: true)
    }
}

// MARK: - Table View
extension SupportSessionViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.row < messages.count else { return UITableViewCell() }
        let message = self.messages[indexPath.row]
        var identifier = ""
        
        if message.message != nil {
            identifier = message.sent ? "sentChat" : "receivedChat"
        } else if message.image != nil {
            identifier = message.sent ? "imageChatSent" : "imageChatReceived"
        } else {
            identifier = message.sent ? "videoChatSent" : "videoChatReceived"
        }
        
        guard !identifier.isEmpty, let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath) as? SupportChatTableViewCell else { return UITableViewCell() }
        cell.loading = message.loading
        guard !message.loading else { return cell }
        
        if let text = message.message {
            cell.messageLabel?.text = text
            cell.messageLabel?.sizeToFit()
        } else if let image = message.image {
            cell.addImage(image, bounds: tableView.bounds)
        } else if let player = message.player {
            cell.addVideo(from: player, bounds: tableView.bounds)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row < messages.count else { return }
        guard let cell = cell as? SupportChatTableViewCell, let player = messages[indexPath.row].player else { return }
        cell.addVideo(from: player, bounds: tableView.bounds)
    }
    
    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row < messages.count else { return }
        guard let cell = cell as? SupportChatTableViewCell, messages[indexPath.row].player != nil else { return }
        cell.stopVideo()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? SupportChatTableViewCell, messages[indexPath.row].player != nil else { return }
        cell.toggleVideo()
    }
}

// MARK: - Remote Support Delegate
extension SupportSessionViewController: RemoteSupportDelegate {
    
    func remoteSupport(willReceiveMessageWith id: UInt16, category: UInt16, numChunksReceived: UInt16, totalChunks: UInt16) {
        guard !messages.contains(where: { $0.id == id }) else { return }
        
        tableView.isHidden = false
        noMessageStackView.isHidden = true
        
        switch category {
        case RSCategory.Chat.rawValue:
            messages.append(ChatMessage(id: Int(id), sent: false, loading: true, message: ""))
            
        case MessageCategory.image.rawValue:
            messages.append(ChatMessage(id: Int(id), sent: false, loading: true, image: UIImage()))
            
        case MessageCategory.video.rawValue:
            messages.append(ChatMessage(id: Int(id), sent: false, loading: true))
            
        default:
            return
        }
        
        self.showNewMessage(with: .left)
    }
    
    func remoteSupport(failedToReceiveMessageWith id: UInt16, category: UInt16) {
        messages.removeAll { $0.id == id }
        
        tableView.isHidden = messages.isEmpty
        noMessageStackView.isHidden = !messages.isEmpty
        tableView.reloadData()
    }
    
    func remoteSupport(didReceive notification: RSNotification) {
        func showMessage(row: Int?) {
            if let row = row {
                let path = IndexPath(row: row, section: 0)
                self.tableView.reloadRows(at: [path], with: .none)
                self.tableView.scrollToRow(at: path, at: .none, animated: true)
            } else {
                self.messages.append(message)
                self.showNewMessage(with: .left)
            }
        }
        
        if notification.category == RSCategory.Chat.rawValue || MessageCategory(rawValue: notification.category)?.isDisplayableMessage == true {
            self.tableView.isHidden = false
            self.noMessageStackView.isHidden = true
        }
        
        let row = messages.firstIndex { $0.id == notification.id }
        let message = messages.first { $0.id == notification.id } ?? ChatMessage(id: Int(notification.id), sent: false)
        message.loading = false
        
        switch notification.category {
        case RSCategory.Chat.rawValue:
            let messageData = Data(notification.data.data)
            message.message = String(data: messageData, encoding: .utf8)
            
        case MessageCategory.image.rawValue:
            message.image = UIImage(data: Data(notification.data.data))
            
        case MessageCategory.video.rawValue:
            print("Received video, attempting to write to file")
            
            let file = "remote-support-\(Int(Date().timeIntervalSince1970 * 1000))"
            Data(notification.data.data).writeMp4DataToLocalUrl(with: file).done(on: DispatchQueue.global(qos: .userInitiated)) { url in
                let player = AVPlayer(url: url)
                message.player = player
            }.done {
                showMessage(row: row)
            }.catch { error in
                print(error)
            }
            
            return
            
        case MessageCategory.diagnosticHeartbeat.rawValue, MessageCategory.deviceData.rawValue:
            return
            
        default:
            print("Received unknown notification")
            return
        }
        
        showMessage(row: row)
    }
    
    func remoteSupport(didReceive command: RSCommand, context: RSCommandContext) {
        if command.category == MessageCategory.bluetoothWriteRequest.rawValue {
            let json = try? JSONSerialization.jsonObject(with: command.data.data) as? [String : Any]
            
            if connectedDevice.isConnected,
                let uuid = json?["uuid"] as? String,
                let encoding = json?["encoding"] as? String,
                let value = json?["value"] as? String,
                let characteristic = connectedDevice.services.flatMap({ $0.value }).first(where: { $0.uuid.uuidString == uuid }),
                let data = encoding == "utf-8" ? value.data(using: .utf8) : value.data(using: .hex)
            {
                connectedDevice.writeValue(data, characteristic: characteristic).done {
                    context.complete()
                }.catch { err in
                    let error = RSError(message: err.localizedDescription, statusCode: 500)
                    self.logger.error(err.localizedDescription)
                    context.error(error)
                }
            } else {
                let errorText = connectedDevice.isConnected ? "Unknown characteristic" : "Not connected to device"
                self.logger.error(errorText)
                context.error(RSError(message: errorText, statusCode: 500))
            }
        } else if command.category == MessageCategory.bluetoothNotifyRequest.rawValue {
            let json = try? JSONSerialization.jsonObject(with: command.data.data) as? [String : Any]
            
            if connectedDevice.isConnected,
               let uuid = json?["uuid"] as? String,
               let setNotify = json?["setNotify"] as? Bool,
               let characteristic = connectedDevice.services.flatMap({ $0.value }).first(where: { $0.uuid.uuidString == uuid })
            {
                connectedDevice.setNotify(characteristic: characteristic, notify: setNotify).done {
                    context.complete()
                }.catch { err in
                    let error = RSError(message: err.localizedDescription, statusCode: 500)
                    context.error(error)
                }
            }
        } else {
            let error = RSError(message: "Received unknown command", statusCode: 500)
            logger.error(error.message)
            context.error(error)
        }
    }
    
    func remoteSupport(didReceive query: RSQuery, context: RSQueryContext) {
        if query.category == MessageCategory.bluetoothReadRequest.rawValue {
            let json = try? JSONSerialization.jsonObject(with: query.data.data) as? [String : Any]
            
            if connectedDevice.isConnected,
                let uuid = json?["uuid"] as? String,
                let characteristic = connectedDevice.services.flatMap({ $0.value }).first(where: { $0.uuid.uuidString == uuid })
            {
                connectedDevice.readValue(from: characteristic).done { value in
                    let decoded = characteristic.parsedTextValue
                    let encoding = characteristic.uuid.uuidString == characteristic.uuid.description ? "hex" : "utf-8"
                    let json: [String : Any] = ["encoding" : encoding, "value" : decoded ?? value.map { String(format: "%02hhx", $0) }.joined()]
                    let response = RSTaggedData(tag: DefaultTag.Object, data: try JSONSerialization.data(withJSONObject: json))
                    context.respond(response, isLastMessage: true)
                }.catch { err in
                    let error = RSError(message: "Failed to read value from characteristic", statusCode: 500)
                    self.logger.error(err.localizedDescription)
                    context.error(error)
                }
            } else {
                let errorText = connectedDevice.isConnected ? "Unknown characteristic" : "Not connected to device"
                logger.error(errorText)
                context.error(RSError(message: errorText, statusCode: 500))
            }
        } else if query.category == MessageCategory.multipartText.rawValue {
            let messageData = Data(query.data.data)
            tableView.isHidden = false
            noMessageStackView.isHidden = true
            messages.append(ChatMessage(sent: false, message: String(data: messageData, encoding: .utf8)))
            showNewMessage(with: .left)
            
            for i in 1...5 {
                guard let message = String(i).data(using: .utf8) else {
                    context.error(RSError(message: "Cannot fulfill multi query", statusCode: 500))
                    return
                }
                
                messages.append(ChatMessage(sent: true, message: String(i)))
                showNewMessage(with: .right)
                context.respond(RSTaggedData(tag: DefaultTag.Chat, data: message), isLastMessage: i == 5)
            }
        } else {
            let error = RSError(message: "Received unknown query", statusCode: 500)
            logger.error(error.message)
            context.error(error)
        }
    }
    
    func remoteSupportDidConnect() {
        self.supportStatusIndicator.setStatus(to: .connected)
        self.supportStatusLabel.text = "Connected with Agent"
        self.sendBluetoothDiagnostics()
        self.heartbeatTimer?.fire()
    }
    
    func remoteSupportDidDisconnect(expected: Bool) {
        self.supportStatusIndicator.setStatus(to: .disconnected)
        self.supportStatusLabel.text = "Disconnected"
        
        if expected {
            self.showAlert(message: "Representative has disconnected from support session") { action in
                self.dismiss(animated: true)
            }
        }
    }
    
    func remoteSupportWillResetConnection() {
        self.supportStatusIndicator.setStatus(to: .reconnecting)
        self.supportStatusLabel.text = "Reconnecting with Agent..."
    }
    
    private func sendBluetoothDiagnostics() {
        guard shouldSendDiagnostics, remoteSupport?.isConnected == true else { return }
        shouldSendDiagnostics = false
        
        do {
            let diagnostics = connectedDevice.getDiagnostics()
            let jsonData = try JSONSerialization.data(withJSONObject: diagnostics)
            let tagged = RSTaggedData(tag: DefaultTag.Object, data: jsonData)
            let notification = RSNotification(category: MessageCategory.deviceData.rawValue, data: tagged)
            remoteSupport?.sendNotification(notification: notification).done {}.catch { error in
                print(error)
            }
        } catch {
            print(error)
        }
    }
}

// MARK: - Bluetooth Delegate
extension SupportSessionViewController: BluetoothStateDelegate, PeripheralDelegate {
    
    var bluetoothStateDelegateId: String {
        return "SupportSessionViewController"
    }
    
    var peripheralDelegateId: String {
        return "SupportSessionViewController"
    }
    
    func didConnectToDevice(_ device: BluetoothDevice) {
        self.deviceStatus = .connected
        self.heartbeatTimer?.fire()
    }
    
    func didDisconnectFromDevice(_ device: BluetoothDevice) {
        guard device.id == self.connectedDevice.id else { return }
        
        self.deviceStatus = .reconnecting
        self.heartbeatTimer?.fire()
        
        self.connectedDevice.connect().catch { [weak self] error in
            self?.deviceStatus = .disconnected
            self?.showAlert(title: "Device Disconnected", message: "Please reconnect your device to your phone to continue troubleshooting.", buttonTitle: "Dismiss")
        }
    }
    
    func didDiscoverServices(for peripheral: CBPeripheral, services: [CBService]) {
        guard self.connectedDevice.id == peripheral.identifier else { return }
        
        self.shouldSendDiagnostics = true
        self.sendBluetoothDiagnostics()
    }
    
    func didDiscoverCharacteristics(for peripheral: CBPeripheral, characteristics: [CBCharacteristic], service: CBService) {
        guard self.connectedDevice.id == peripheral.identifier else { return }
        
        characteristics.forEach { self.connectedDevice.readValue(from: $0).cauterize() }
    }
    
    func didUpdateDescriptor(for peripheral: CBPeripheral, descriptor: CBDescriptor) {
        guard self.connectedDevice.id == peripheral.identifier else { return }
        
        self.shouldSendDiagnostics = true
        self.sendBluetoothDiagnostics()
    }
    
    func didScanAdvertisedData(for device: BluetoothDevice) {
        guard self.connectedDevice.id == device.id else { return }
        
        self.connectedDevice.updateDevice(with: device)
    }
    
    func didUpdateCharacteristic(for peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard self.connectedDevice.id == peripheral.identifier else { return }
        
        self.shouldSendDiagnostics = true
        self.sendBluetoothDiagnostics()
    }
}

// MARK: - Image Picker
extension SupportSessionViewController: UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        self.mediaImageView.subviews.forEach({ $0.removeFromSuperview() })
        self.mediaImageView.layer.sublayers?.forEach({ $0.removeFromSuperlayer() })
        info.forEach {
            print($0.key.rawValue)
        }
        
        if let image = info[.originalImage] as? UIImage {
            self.setupImage(image)
        } else if let videoUrl = info[.mediaURL] as? URL {
            self.setupVideo(url: videoUrl)
        } else if let asset = info[.phAsset] as? PHAsset {
            self.setupAsset(asset)
        } else if PHPhotoLibrary.authorizationStatus() != .authorized  {
            if let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(url) {
                let alert = UIAlertController(title: "Error", message: "Permission is required to access files in the Photos app. Would you like to access Settings to change that permission?", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(title: "Yes", style: .default) { action in
                    UIApplication.shared.open(url)
                })
                present(alert, animated: true)
            } else {
                showAlert(title: "Error", message: "Cannot access that file")
            }
        }
    }
    
    /// Sets up an image in the media view above the chat textfield
    private func setupImage(_ image: UIImage) {
        UIView.animate(withDuration: 0.2, delay: 0, options: UIView.AnimationOptions.transitionCurlUp, animations: {
            let size = self.getMediaSize(bounds: self.chatTextField.bounds, naturalMediaSize: image.size)
            self.mediaImageView.image = image
            self.mediaImageViewWidth.constant = size.width
            self.mediaViewHeightConstraint.constant = size.height + 10
            self.mediaImageViewHeightComparisonConstraint.constant = -10
            
            let aspectRatio = NSLayoutConstraint(item: self.mediaImageView!, attribute: .height, relatedBy: .equal, toItem: self.mediaImageView, attribute: .width, multiplier: size.height / size.width, constant: 0)
            aspectRatio.priority = .defaultHigh
            self.mediaImageView.addConstraint(aspectRatio)
            
            self.addCancelButton()
            
            self.view.layoutIfNeeded()
        })
    }
    
    /// Sets up a video in the media view above the chat textfield
    /// - Parameter url: `URL` of the video to set up
    /// - Parameter existingPlayer: Optional `AVPlayer` for videos that come from a `PHAsset`
    private func setupVideo(url: URL, existingPlayer: AVPlayer? = nil) {
        self.videoUrl = url
        self.sendButton.isEnabled = true
        
        UIView.animate(withDuration: 0.2, delay: 0, options: UIView.AnimationOptions.transitionCurlUp, animations: {
            let player = existingPlayer ?? AVPlayer(url: url)
            guard let asset = player.currentItem?.asset, let track = asset.tracks(withMediaType: .video).first else { return }
            
            let videoLength = asset.duration.seconds
            let videoSize = track.naturalSize.applying(track.preferredTransform)
            let size = self.getMediaSize(bounds: self.chatTextField.bounds, naturalMediaSize: CGSize(width: abs(videoSize.width), height: abs(videoSize.height)))
            
            self.mediaImageViewWidth?.constant = size.width
            self.mediaViewHeightConstraint?.constant = size.height + 10
            self.mediaImageViewHeightComparisonConstraint.constant = -10
            
            let aspectRatio = NSLayoutConstraint(item: self.mediaImageView!, attribute: .height, relatedBy: .equal, toItem: self.mediaImageView, attribute: .width, multiplier: size.height / size.width, constant: 0)
            aspectRatio.priority = .defaultHigh
            self.mediaImageView.addConstraint(aspectRatio)
            
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = AVLayerVideoGravity.resizeAspect
            playerLayer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            self.mediaImageView?.layer.insertSublayer(playerLayer, at: 0)
            
            let minutes = Int(videoLength) / 60 % 60
            let seconds = Int(videoLength) % 60
            self.addVideoDecorators(minutes: minutes, seconds: seconds)
        })
    }
    
    /// Sets up a `PHAsset` in the media view above the chat textfield
    private func setupAsset(_ asset: PHAsset) {
        if asset.mediaType == .image {
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight), contentMode: .aspectFit, options: nil) { img, _ in
                guard let image = img else { return }
                DispatchQueue.main.async {
                    self.setupImage(image)
                }
            }
        } else if asset.mediaType == .video {
            PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { ast, _, _ in
                guard let asset = ast, let urlAsset = asset as? AVURLAsset else { return }
                let item = AVPlayerItem(asset: asset)
                let player = AVPlayer(playerItem: item)
                DispatchQueue.main.async {
                    self.setupVideo(url: urlAsset.url, existingPlayer: player)
                }
            }
        }
    }
    
    /// Given the surrounding bounds (text message UITextField), return an applicable size for the media to be shown in
    private func getMediaSize(bounds: CGRect, naturalMediaSize size: CGSize) -> CGSize {
        let maxHeight: CGFloat = 170
        let maxWidth = bounds.width * 0.8
        
        var height = maxHeight
        let scale = height / size.height
        var width = size.width * scale
        
        if width > maxWidth {
            let newScale = maxWidth / width
            width = maxWidth
            height *= newScale
        }
        
        return CGSize(width: width, height: height)
    }
    
    /// Adds visual indicators to a video that is ready to send
    private func addVideoDecorators(minutes: Int, seconds: Int) {
        addCancelButton()
        
        // Add video length label
        let timeString = String(format:"%2i:%02i", minutes, seconds)
        let timeLabel = UILabel()
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.backgroundColor = UIColor.lightGray.withAlphaComponent(0.6)
        timeLabel.text = timeString
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textAlignment = .center
        timeLabel.sizeToFit()
        let labelWidth = timeLabel.bounds.width
        let labelHeight = timeLabel.bounds.height
        timeLabel.frame = CGRect(x: 0, y: 0, width: labelWidth + 6, height: labelHeight)
        timeLabel.layer.cornerRadius = timeLabel.bounds.height / 2
        timeLabel.layer.masksToBounds = true
        let timeLabelConstraints = [
            NSLayoutConstraint(item: timeLabel, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: labelWidth + 6),
            NSLayoutConstraint(item: timeLabel, attribute: .right, relatedBy: .equal, toItem: self.mediaImageView, attribute: .right, multiplier: 1, constant: -10),
            NSLayoutConstraint(item: timeLabel, attribute: .bottom, relatedBy: .equal, toItem: self.mediaImageView, attribute: .bottom, multiplier: 1, constant: -7)
        ]
        self.mediaImageView.addSubview(timeLabel)
        self.mediaImageView.addConstraints(timeLabelConstraints)
        
        // Add camera icon
        let cameraIcon = UIImageView(frame: CGRect(x: 0, y: 0, width: 23, height: 14))
        cameraIcon.translatesAutoresizingMaskIntoConstraints = false
        cameraIcon.image = #imageLiteral(resourceName: "video")
        let cameraIconConstraints = [
            NSLayoutConstraint(item: cameraIcon, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 23),
            NSLayoutConstraint(item: cameraIcon, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 14),
            NSLayoutConstraint(item: cameraIcon, attribute: .bottom, relatedBy: .equal, toItem: self.mediaImageView, attribute: .bottom, multiplier: 1, constant: -9),
            NSLayoutConstraint(item: cameraIcon, attribute: .left, relatedBy: .equal, toItem: self.mediaImageView, attribute: .left, multiplier: 1, constant: 10),
        ]
        self.mediaImageView.addSubview(cameraIcon)
        self.mediaImageView.addConstraints(cameraIconConstraints)
        
        self.view.layoutIfNeeded()
    }

    private func addCancelButton() {
        // Add button to be able to get rid of image
        let cancelButton = UIButton(frame: CGRect(x: 0, y: 0, width: 18, height: 18))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setImage(#imageLiteral(resourceName: "close"), for: .normal)
        cancelButton.addTarget(self, action: #selector(self.cancelMedia), for: .touchUpInside)
        self.mediaImageView.addSubview(cancelButton)
        
        let cancelButtonConstraints = [
            NSLayoutConstraint(item: cancelButton, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 18),
            NSLayoutConstraint(item: cancelButton, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 18),
            NSLayoutConstraint(item: cancelButton, attribute: .top, relatedBy: .equal, toItem: self.mediaImageView, attribute: .top, multiplier: 1, constant: 5),
            NSLayoutConstraint(item: cancelButton, attribute: .right, relatedBy: .equal, toItem: self.mediaImageView, attribute: .right, multiplier: 1, constant: -5)
        ]
        self.mediaImageView.addConstraints(cancelButtonConstraints)
        
        self.mediaViewSpacerHeightConstraint.constant = 0.5
        self.sendButton.isEnabled = true
        self.chatTextField.placeholder = "Add comment or send"
    }
    
    /// Gets rid of any media that is ready to send
    @objc private func cancelMedia() {
        self.videoUrl = nil
        self.sendButton.isEnabled = false
        self.chatTextField.placeholder = "Enter message..."
        UIView.animate(withDuration: 0.2, delay: 0, options: UIView.AnimationOptions.transitionCurlDown, animations: {
            self.mediaViewHeightConstraint.constant = 0
            self.mediaImageView.subviews.forEach({ $0.removeFromSuperview() })
            self.mediaViewSpacerHeightConstraint.constant = 0
            self.mediaImageViewHeightComparisonConstraint.constant = 0
            self.view.layoutIfNeeded()
        }, completion: { _ in
            self.mediaImageView.image = nil
            self.mediaImageView.layer.sublayers?.forEach({ $0.removeFromSuperlayer() })
        })
    }
}

// MARK: - Keyboard
extension SupportSessionViewController {
    
    @objc func keyboardNotification(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue
            let isKeyboardDisplayed = keyboardFrame.origin.y < UIScreen.main.bounds.size.height
            let bottomConstraintConstant = isKeyboardDisplayed ? keyboardFrame.size.height + 17 : 17
            let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
            let animationCurveRawNSN = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber
            let animationCurveRaw = animationCurveRawNSN?.uintValue ?? UIView.AnimationOptions.curveEaseInOut.rawValue
            let animationCurve = UIView.AnimationOptions(rawValue: animationCurveRaw)

            UIView.animate(withDuration: duration, delay: 0, options: animationCurve, animations: {
                if let constraint = self.logHeightConstraint, let view = self.logContainerView {
                    self.view.removeConstraint(constraint)
                    let multiplier: CGFloat = isKeyboardDisplayed ? 0 : 0.175
                    let constraint = NSLayoutConstraint(item: view, attribute: .height, relatedBy: .equal, toItem: view.superview, attribute: .height, multiplier: multiplier, constant: 0)
                    self.logHeightConstraint = constraint
                    self.view.addConstraint(constraint)
                }
                
                self.logContainerView.isHidden = isKeyboardDisplayed
                self.bottomConstraint.constant = bottomConstraintConstant
                self.view.layoutIfNeeded()
            }, completion: { complete in
                guard self.messages.count > 0 else { return }
                self.tableView.scrollToRow(at: IndexPath(row: self.messages.count - 1, section: 0), at: .bottom, animated: true)
            })
        }
    }
}

extension SupportSessionViewController: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let newText = (textField.text! as NSString).replacingCharacters(in: range, with: string)
        
        sendButton.isEnabled = !newText.isEmpty
        
        return true
    }
}

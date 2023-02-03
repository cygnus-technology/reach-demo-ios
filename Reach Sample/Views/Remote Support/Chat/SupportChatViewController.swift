//
//  SupportChatViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 5/31/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import UIKit
import AVFoundation
import AVKit
import Photos
import MobileCoreServices
import PromiseKit
import RemoteSupport
import Combine

class SupportChatViewController: UIViewController, SupportTabViewController {
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var noMessageView: UIView!
    
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
    
    var logger: TextViewLogger { SupportService.shared.logger }
    var messages: [ChatMessage] { SupportService.shared.messages }
    private var videoUrl: URL?
    private var bag = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        SupportService.shared.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in self?.setViews() }
            .store(in: &bag)
        
        SupportService.shared.onMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in self?.showNewMessage(message) }
            .store(in: &bag)
        
        SupportService.shared.onMessageError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in self?.handleMessageError(id) }
            .store(in: &bag)
        
        SupportService.shared.onReloadMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in self?.reloadMessage(message) }
            .store(in: &bag)
        
        sendButton.setImage(#imageLiteral(resourceName: "send"), for: .disabled)
        sendButton.setImage(#imageLiteral(resourceName: "send-orange"), for: .normal)
        
        tableView.tableFooterView = UIView()
        tableView.estimatedRowHeight = 56
        
        let rightView = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        chatTextField.delegate = self
        chatTextField.rightView = rightView
        chatTextField.rightViewMode = .always
        
        if PHPhotoLibrary.authorizationStatus() == .notDetermined  {
            PHPhotoLibrary.requestAuthorization { status in }
        }
        
        scrollToBottom()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardNotification(notification:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        SupportService.shared.clearMessages()
        tableView.reloadData()
        showToast(message: "Device ran out of memory. Clearing message history to free up some space")
    }
    
    @IBAction func sendButtonTapped(_ sender: Any) {
        chatTextField.resignFirstResponder()
        sendActivityIndicator.startAnimating()
        sendButton.isHidden = true
        var mediaPromise = Promise()
        var textPromise = Promise()
        
        if let image = mediaImageView.image {
            print("Sending image")
            mediaPromise = SupportService.shared.sendImage(image).done { [weak self] in
                self?.cancelMedia()
            }
        } else if let videoUrl = videoUrl {
            print("Sending video")
            mediaPromise = mediaPromise.then {
                SupportService.shared.sendVideo(videoUrl)
            }.done { [weak self] in
                self?.cancelMedia()
            }
        }
        
        if let message = chatTextField.text, !message.isEmpty {
            let promise = SupportService.shared.sendMessage(message)
            chatTextField.text = ""
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
    
    private func setViews() {
        tableView.isHidden = messages.isEmpty
        noMessageView.isHidden = !messages.isEmpty
    }
    
    private func showNewMessage(_ message: ChatMessage) {
        let animation: UITableView.RowAnimation = message.sent ? .right : .left
        let indexPaths = [IndexPath(row: messages.count - 1, section: 0)]
        tableView.insertRows(at: indexPaths, with: animation)
        tableView.scrollToRow(at: indexPaths.first!, at: .bottom, animated: true)
    }
    
    private func handleMessageError(_ id: Int) {
        tableView.reloadData()
    }
    
    private func reloadMessage(_ message: ChatMessage) {
        let row = messages.firstIndex { $0.id == message.id }
        if let row = row {
            let path = IndexPath(row: row, section: 0)
            tableView.reloadRows(at: [path], with: .none)
            tableView.scrollToRow(at: path, at: .none, animated: true)
        }
    }
    
    private func scrollToBottom() {
        DispatchQueue.main.async {
            guard !self.messages.isEmpty else { return }
            self.tableView.scrollToRow(at: IndexPath(row: self.messages.count - 1, section: 0), at: .bottom, animated: true)
        }
    }
}

// MARK: - Table View
extension SupportChatViewController: UITableViewDelegate, UITableViewDataSource {
    
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

extension SupportChatViewController: UITextFieldDelegate {
    
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

// MARK: - Image Picker
extension SupportChatViewController: UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    
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
extension SupportChatViewController {
    
    @objc func keyboardNotification(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue
            let isKeyboardDisplayed = keyboardFrame.origin.y < UIScreen.main.bounds.size.height
            let tabBarHeight = tabBarController?.tabBar.bounds.height ?? 0
            let bottomConstraintConstant = isKeyboardDisplayed ? keyboardFrame.size.height - tabBarHeight : 20
            let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
            let animationCurveRawNSN = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber
            let animationCurveRaw = animationCurveRawNSN?.uintValue ?? UIView.AnimationOptions.curveEaseInOut.rawValue
            let animationCurve = UIView.AnimationOptions(rawValue: animationCurveRaw)

            UIView.animate(withDuration: duration, delay: 0, options: animationCurve, animations: {
                self.noMessageView.alpha = isKeyboardDisplayed ? 0 : 1
                self.bottomConstraint.constant = bottomConstraintConstant
                self.view.layoutIfNeeded()
            }, completion: { complete in
                self.scrollToBottom()
            })
        }
    }
}

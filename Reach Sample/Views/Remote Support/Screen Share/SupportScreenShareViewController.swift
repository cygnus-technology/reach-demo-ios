//
//  SupportScreenShareViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 6/9/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import UIKit
import RemoteSupport
import Combine

class SupportScreenShareViewController: UIViewController, SupportTabViewController {

    @IBOutlet weak var inactiveView: UIView!
    @IBOutlet weak var activeView: UIView!
    @IBOutlet weak var shareButton: PrimaryButton!
    @IBOutlet weak var endButton: PrimaryButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    var remoteSupport: RemoteSupportClient? { SupportService.shared.remoteSupport }
    var screenController: ScreenCaptureController? { SupportService.shared.screenController }
    private var bag = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        SupportService.shared.$isScreenShareOn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOn in self?.screenToggled(isOn) }
            .store(in: &bag)
        
        remoteSupport?.onScreenCapture
            .receive(on: DispatchQueue.main)
            .sink { [weak self] args in self?.handleScreenCapture(args) }
            .store(in: &bag)
        
        remoteSupport?.onScreenCaptureFailed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in self?.handleScreenCaptureError(error) }
            .store(in: &bag)
    }
    
    @IBAction func shareButtonTapped(_ sender: Any) {
        if let controller = screenController {
            activityIndicator.startAnimating()
            controller.start().done {
                SupportService.shared.isScreenShareOn = true
                self.sendStart()
            }.catch { error in
                self.handleScreenCaptureError(error)
            }
        } else if SupportService.shared.startScreenShare() {
            activityIndicator.startAnimating()
            activeView.isHidden = false
            inactiveView.isHidden = true
            sendStart()
        }
    }
    
    @IBAction func endButtonTapped(_ sender: Any) {
        SupportService.shared.stopScreenShare()
        stopScreenShare()
        sendStop()
    }
    
    private func screenToggled(_ isOn: Bool) {
        if isOn, let controller = screenController {
            handleScreenCapture(ScreenCaptureEventArgs(controller: controller))
        } else {
            stopScreenShare()
        }
    }
    
    private func stopScreenShare() {
        endButton.isHidden = true
        shareButton.isHidden = false
        activeView.isHidden = true
        inactiveView.isHidden = false
        tabBarItem.image = Assets.screenShareDisabled.image
        tabBarItem.selectedImage = Assets.screenShare.image
    }
    
    /// Sends a notification to the web to signify that streaming has started
    private func sendStart() {
        let tagged = WellKnownTagEncoder.Number.encode(
            type: Int32.self, MediaSharingType.screen.rawValue, tag: .int)
        let notification = RSNotification(category: MessageCategory.startSharing.rawValue, data: tagged)
        remoteSupport?.sendNotification(notification: notification).cauterize()
    }
    
    /// Sends a notification to the web to signify that streaming has stopped
    private func sendStop() {
        let tagged = WellKnownTagEncoder.Number.encode(
            type: Int32.self, MediaSharingType.screen.rawValue, tag: .int)
        let notification = RSNotification(category: MessageCategory.stopSharing.rawValue, data: tagged)
        remoteSupport?.sendNotification(notification: notification).cauterize()
    }
}

extension SupportScreenShareViewController {
    
    private func handleScreenCapture(_ args: ScreenCaptureEventArgs) {
        activityIndicator.stopAnimating()
        shareButton.isEnabled = true
        shareButton.isHidden = true
        endButton.isHidden = false
        activeView.isHidden = false
        inactiveView.isHidden = true
        tabBarItem.image = Assets.screenShareActive.image
        tabBarItem.selectedImage = Assets.screenShareActive.image
    }
    
    private func handleScreenCaptureError(_ error: Error) {
        activityIndicator.stopAnimating()
        shareButton.isEnabled = true
        shareButton.isHidden = false
        endButton.isHidden = true
        activeView.isHidden = true
        inactiveView.isHidden = false
        showToast(message: error.localizedDescription)
        tabBarItem.image = Assets.screenShareDisabled.image
        tabBarItem.selectedImage = Assets.screenShare.image
    }
}

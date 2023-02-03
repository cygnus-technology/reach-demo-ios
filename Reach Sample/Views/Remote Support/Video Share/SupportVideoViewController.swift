//
//  SupportVideoViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 6/1/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import UIKit
import RemoteSupport
import WebRTC
import Combine

class SupportVideoViewController: UIViewController, SupportTabViewController {

    @IBOutlet weak var inactiveView: UIView!
    @IBOutlet weak var activeView: RTCMTLVideoView!
    @IBOutlet weak var shareButton: PrimaryButton!
    @IBOutlet weak var endButton: PrimaryButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var cameraActivityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var cameraButtons: UIStackView!
    
    var remoteSupport: RemoteSupportClient? { SupportService.shared.remoteSupport }
    var videoController: CameraStreamController? { SupportService.shared.videoController }
    private var bag = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        SupportService.shared.$isVideoShareOn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOn in self?.videoToggled(isOn) }
            .store(in: &bag)
        
        remoteSupport?.onVideoCapture
            .receive(on: DispatchQueue.main)
            .sink { [weak self] args in self?.handleVideoCapture(args) }
            .store(in: &bag)
        
        remoteSupport?.onVideoCaptureFailed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in self?.handleVideoCaptureError(error) }
            .store(in: &bag)
    }
    
    @IBAction func shareButtonTapped(_ sender: Any) {
        if let controller = videoController {
            activityIndicator.startAnimating()
            controller.start().done {
                SupportService.shared.isVideoShareOn = true
                self.sendStart()
            }.catch { error in
                self.handleVideoCaptureError(error)
            }
        } else if SupportService.shared.startVideoStream() {
            activityIndicator.startAnimating()
            activeView.isHidden = false
            inactiveView.isHidden = true
            sendStart()
        }
    }
    
    @IBAction func endButtonTapped(_ sender: Any) {
        SupportService.shared.stopVideoStream()
        stopVideoStream()
        sendStop()
    }
    
    @IBAction func switchCameraTapped(_ sender: Any) {
        cameraButtons.isHidden = true
        cameraActivityIndicator.startAnimating()
        SupportService.shared.flipCamera().catch { error in
            self.showAlert(title: "Error", message: error.localizedDescription)
        }.finally {
            self.cameraActivityIndicator.stopAnimating()
            self.cameraButtons.isHidden = false
        }
    }
    
    private func videoToggled(_ isOn: Bool) {
        if isOn, let controller = videoController {
            handleVideoCapture(VideoCaptureEventArgs(controller: controller))
        } else {
            stopVideoStream()
        }
    }
    
    private func stopVideoStream() {
        endButton.isHidden = true
        shareButton.isHidden = false
        activeView.isHidden = true
        videoController?.removeVideoSink(sink: activeView)
        inactiveView.isHidden = false
        cameraButtons.isHidden = true
        tabBarItem.image = Assets.videoDisabled.image
        tabBarItem.selectedImage = Assets.video.image
    }
    
    /// Sends a notification to the web to signify that streaming has started
    private func sendStart() {
        let tagged = WellKnownTagEncoder.Number.encode(
            type: Int32.self, MediaSharingType.video.rawValue, tag: .int)
        let notification = RSNotification(category: MessageCategory.startSharing.rawValue, data: tagged)
        remoteSupport?.sendNotification(notification: notification).cauterize()
    }
    
    /// Sends a notification to the web to signify that streaming has stopped
    private func sendStop() {
        let tagged = WellKnownTagEncoder.Number.encode(
            type: Int32.self, MediaSharingType.video.rawValue, tag: .int)
        let notification = RSNotification(category: MessageCategory.stopSharing.rawValue, data: tagged)
        remoteSupport?.sendNotification(notification: notification).cauterize()
    }
}

extension SupportVideoViewController {
    
    private func handleVideoCapture(_ args: VideoCaptureEventArgs) {
        activityIndicator.stopAnimating()
        shareButton.isEnabled = true
        shareButton.isHidden = true
        endButton.isHidden = false
        args.controller.addVideoSink(sink: activeView)
        activeView.isHidden = false
        inactiveView.isHidden = true
        cameraButtons.isHidden = false
        tabBarItem.image = Assets.videoActive.image
        tabBarItem.selectedImage = Assets.videoActive.image
    }
    
    private func handleVideoCaptureError(_ error: Error) {
        activityIndicator.stopAnimating()
        shareButton.isEnabled = true
        shareButton.isHidden = false
        endButton.isHidden = true
        activeView.isHidden = true
        inactiveView.isHidden = false
        cameraButtons.isHidden = true
        showToast(message: error.localizedDescription)
        tabBarItem.image = Assets.videoDisabled.image
        tabBarItem.selectedImage = Assets.video.image
    }
}

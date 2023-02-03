//
//  SupportChatTableViewCell.swift
//  Reach Sample
//
//  Created by Cygnus on 1/14/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import UIKit
import AVKit

fileprivate let VIDEO_BOUNDS_RATIO: CGFloat = 0.82

class SupportChatTableViewCell: UITableViewCell {
    @IBOutlet weak var messageLabel: ChatTextView?
    @IBOutlet weak var messageImageView: UIImageView?
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    @IBOutlet weak var imageViewWidthConstraint: NSLayoutConstraint?
    @IBOutlet weak var imageViewHeightConstraint: NSLayoutConstraint?
    
    @IBOutlet weak var videoContainerView: UIView?
    @IBOutlet weak var videoHeightConstraint: NSLayoutConstraint?
    @IBOutlet weak var videoWidthConstraint: NSLayoutConstraint?
    @IBOutlet weak var videoPlayImageView: UIImageView?
    
    private var videoPlayer: AVPlayer?
    
    var loading: Bool = false {
        didSet {
            loading ? activityIndicator.startAnimating() : activityIndicator.stopAnimating()
            videoPlayImageView?.isHidden = loading
            messageImageView?.backgroundColor = loading ? .lightGray : .clear
            videoContainerView?.backgroundColor = loading ? .lightGray : .clear
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        messageImageView?.layer.cornerRadius = 5
        messageImageView?.layer.masksToBounds = true
        videoContainerView?.layer.cornerRadius = 5
        videoContainerView?.layer.masksToBounds = true
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
    func addImage(_ image: UIImage, bounds: CGRect) {
        let size = self.getMediaSize(from: bounds, naturalMediaSize: image.size)
        messageImageView?.image = image
        imageViewHeightConstraint?.constant = size.height
        imageViewWidthConstraint?.constant = size.width
    }

    func addVideo(from player: AVPlayer, bounds: CGRect) {
        // Remove any previous video layers
        videoContainerView?.layer.sublayers?.forEach({ $0.removeFromSuperlayer() })
        
        guard let track = player.currentItem?.asset.tracks(withMediaType: .video).first else { return }
        let videoSize = track.naturalSize.applying(track.preferredTransform)
        let size = self.getMediaSize(from: bounds, naturalMediaSize: CGSize(width: abs(videoSize.width), height: abs(videoSize.height)))
        
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = AVLayerVideoGravity.resizeAspect
        playerLayer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        player.actionAtItemEnd = .pause
        
        self.videoPlayer = player
        self.videoWidthConstraint?.constant = size.width
        self.videoHeightConstraint?.constant = size.height
        self.videoContainerView?.layer.insertSublayer(playerLayer, at: 0)
    }
    
    @objc func toggleVideo() {
        guard let videoPlayer = self.videoPlayer else { return }
        
        if videoPlayer.isPlaying {
            videoPlayer.pause()
            self.videoPlayImageView?.isHidden = false
        } else {
            videoPlayer.seek(to: .zero) { finished in
                if finished {
                    self.videoPlayImageView?.isHidden = true
                    videoPlayer.play()
                }
            }
        }
    }
    
    func stopVideo() {
        self.videoPlayer?.pause()
        self.videoPlayImageView?.isHidden = false
    }
    
    /// Determines an appropriate size for displayed media given a parent view's bounds
    private func getMediaSize(from bounds: CGRect, naturalMediaSize size: CGSize) -> CGSize {
        let maxWidth = bounds.width * VIDEO_BOUNDS_RATIO
        let maxHeight = bounds.height * VIDEO_BOUNDS_RATIO
        
        if size.width < maxWidth && size.height < maxHeight {
            return size
        }
        
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
}

extension AVPlayer {
    var isPlaying: Bool {
        return rate != 0 && error == nil
    }
}

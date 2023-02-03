//
//  AppDelegate.swift
//  Reach Sample
//
//  Created by Cygnus on 1/13/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import UIKit
import AVFoundation

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Configure video
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .moviePlayback)
        } catch {
            print("Setting category to AVAudioSessionCategoryPlayback failed.")
        }
        
        // Configure navigation bars
        let appearance = UINavigationBarAppearance()
        let attributes: [NSAttributedString.Key : Any] = [
            .foregroundColor : UIColor.white,
            .font : UIFont.systemFont(ofSize: 16)
        ]
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = attributes
        appearance.largeTitleTextAttributes = attributes
        appearance.backgroundColor = Colors.primary.color
        appearance.shadowImage = UIImage()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        
        return true
    }
}


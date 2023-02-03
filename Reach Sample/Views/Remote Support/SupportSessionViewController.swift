//
//  SupportSessionViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 1/14/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import UIKit
import CoreBluetooth
import RemoteSupport
import PromiseKit
import Combine

class SupportSessionViewController: UITabBarController {
    
    @IBOutlet weak var minimizeButton: UIBarButtonItem!
    
    var logger: TextViewLogger { SupportService.shared.logger }
    
    private var tabs = [SupportTabViewController]()
    private var bag = Set<AnyCancellable>()
    
    private var deviceStatusIndicator: ConnectionStatusIndicator?
    private var deviceStatusLabel: UILabel?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // TODO: Include minimize button
        navigationItem.rightBarButtonItems?.removeAll { $0 == minimizeButton }
        
        SupportService.shared.$selectedDevice
            .receive(on: DispatchQueue.main)
            .sink { device in }
            .store(in: &bag)
        
        SupportService.shared.$deviceStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.setDeviceStatus(status) }
            .store(in: &bag)
        
        SupportService.shared.onSessionEnded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.dismiss(animated: true) }
            .store(in: &bag)
        
        tabBar.unselectedItemTintColor = UIColor.white.withAlphaComponent(0.6)
        setSelectedItemImage(barWidth: tabBar.bounds.width)
        setupDeviceIndicator()
        
        tabs = viewControllers?.compactMap {
            _ = $0.view // Load child view controllers's views
            return $0 as? SupportTabViewController
        } ?? []
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate { context in
            self.setSelectedItemImage(barWidth: size.width)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let destination = segue.destination as? SupportOptionsViewController {
            destination.connectDevice = connectDevice
            destination.disconnectDevice = disconnectDevice
            destination.endSupport = endSupport
            destination.popoverPresentationController?.delegate = self
        }
    }
    
    @IBAction func minimizeTapped(_ sender: Any) {
        dismiss(animated: true)
    }
    
    private func endSupport() {
        let alert = UIAlertController(title: nil, message: "Are you sure you wish to end this support session?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "End Session", style: .destructive) { action in
            SupportService.shared.endSession()
            self.dismiss(animated: true)
        })
        
        present(alert, animated: true)
    }
    
    private func connectDevice() {
        selectedIndex = Tabs.device.rawValue
        let deviceTab = tabs.compactMap { $0 as? SupportDeviceViewController }.first
        deviceTab?.performSegue(withIdentifier: "connectDevice", sender: self)
    }
    
    private func disconnectDevice() {
        guard SupportService.shared.selectedDevice != nil else { return }
        let alert = UIAlertController(title: nil, message: "Are you sure you wish to disconnect from this device?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Disconnect", style: .destructive) { action in
            SupportService.shared.disconnectDevice()
        })
        
        present(alert, animated: true)
    }
    
    private func setSelectedItemImage(barWidth: CGFloat) {
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        let vertical: CGFloat = isPhone ? 2 : 6
        let verticalMargin: CGFloat = vertical * 2 // Vertical pixels for each side
        let horizontalMargin: CGFloat = 8 * 2 * 4 // Horizontal pixels for each side, 4 items
        let totalWidth = barWidth - horizontalMargin
        let width = totalWidth / 4
        let height = tabBar.bounds.height - verticalMargin
        let size = CGSize(width: width, height: height)
        let image = UIColor.white.image(size).rounded(radius: 6)
        tabBar.selectionIndicatorImage = image
    }
    
    private func setupDeviceIndicator() {
        guard let view = Bundle.main.loadNibNamed("ConnectionStatusIndicator", owner: nil)?.first as? UIView,
              let stackView = view.subviews.first as? UIStackView,
              let indicator = stackView.subviews.compactMap({ $0 as? ConnectionStatusIndicator }).first,
              let label = stackView.subviews.compactMap({ $0 as? UILabel }).first
        else { return }
        deviceStatusIndicator = indicator
        deviceStatusLabel = label
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: stackView)
    }
    
    private func setDeviceStatus(_ status: ConnectionStatus) {
        let device = SupportService.shared.selectedDevice
        var statusString = ""
        switch status {
        case .connected:
            statusString = device?.name ?? "Unnamed"
        case .reconnecting:
            statusString = "Reconnecting to \(device?.name ?? "Unnamed")"
        case .disconnected:
            statusString = "No Device Connected"
        }
        
        deviceStatusIndicator?.setStatus(to: status)
        deviceStatusLabel?.text = statusString
    }
}

extension SupportSessionViewController: UIPopoverPresentationControllerDelegate {
    
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
}

enum Tabs: Int {
    case device
    case messaging
    case videoShare
    case screenShare
}

//
//  ViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 1/13/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import UIKit
import CoreBluetooth

fileprivate enum DeviceSortCriteria {
    case alphabetically
    case signalStrength
}

class AvailableDevicesViewController: UIViewController {
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var sortButton: UIButton!
    @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
    
    fileprivate var sortCriteria = DeviceSortCriteria.signalStrength
    fileprivate var selectedDevice: BluetoothDevice?
    fileprivate var initialLoadComplete = false
    
    /// User is trying to connect to a device from a support session
    var supportSessionConnect = false
    var bluetoothStateDelegateId: String = "AvailableDevicesViewController"
    var peripheralDelegateId: String = "AvailableDevicesViewController"
    var scannedDevices = [BluetoothDevice]()
    var queryText = "" {
        didSet {
            DispatchQueue.main.async {
                self.setDevices()
                self.tableView.reloadData()
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setDevices()
        
        searchBar.delegate = self
        searchBar.backgroundImage = Colors.accent.color.image(CGSize(width: searchBar.bounds.width, height: searchBar.bounds.height))
        searchBar.searchTextField.delegate = self
        searchBar.searchTextField.backgroundColor = Colors.accent.color
        searchBar.searchTextField.addPadding(.right(sortButton.bounds.width))
        searchBar.searchTextField.leftView?.tintColor = .white
        searchBar.searchTextField.clearButtonMode = .never
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.tableFooterView = UIView()
        tableView.refreshControl = UIRefreshControl()
        tableView.refreshControl?.addTarget(self, action: #selector(reloadDevices), for: .valueChanged)
        
        if !supportSessionConnect {
            navigationItem.leftBarButtonItem = nil
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardNotification(notification:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        
        for indexPath in tableView.indexPathsForSelectedRows ?? [] {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        
        BluetoothManager.shared.startScanning().done {
            if !self.initialLoadComplete {
                // Show spinner in refresh control
                self.tableView.setContentOffset(CGPoint(x: 0, y: self.tableView.contentOffset.y - (self.tableView.refreshControl?.frame.height ?? 0)), animated: false)
                
                // Begin refreshing
                self.tableView.refreshControl?.beginRefreshing()
                self.tableView.refreshControl?.sendActions(for: .valueChanged)
                self.initialLoadComplete = true
            }
        }.catch { error in
            self.showAlert(message: error.localizedDescription)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        NotificationCenter.default.removeObserver(self)
        BluetoothManager.shared.scannedDevices.forEach { $0.unsubscribeFromPeripheralUpdates(self) }
        BluetoothManager.shared.stopScanning()
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        return selectedDevice != nil
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let destination = segue.destination as? SelectedDeviceViewController
        {
            destination.connectedDevice = selectedDevice
            destination.supportSessionConnect = supportSessionConnect
        }
    }
    
    @IBAction func sortButtonTapped(_ sender: Any) {
        let sortAction = UIAlertController(title: nil, message: "Change your preferred sorting method", preferredStyle: .actionSheet)
        sortAction.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sortAction.addAction(UIAlertAction(title: "Alphabetically", style: .default) { action in
            self.sortCriteria = .alphabetically
            self.sortDevices()
            self.reloadTableView()
        })
        sortAction.addAction(UIAlertAction(title: "Signal Strength", style: .default) { action in
            self.sortCriteria = .signalStrength
            self.sortDevices()
            self.reloadTableView()
        })
        
        sortAction.popoverPresentationController?.sourceView = sortButton
        sortAction.popoverPresentationController?.sourceRect = sortButton.bounds
        present(sortAction, animated: true, completion: nil)
    }
    
    @IBAction func closeButtonTapped(_ sender: Any) {
        dismiss(animated: true)
    }
    
    @objc private func reloadDevices() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { timer in
            self.setDevices()
            self.sortDevices()
            self.reloadTableView()
            self.tableView.refreshControl?.endRefreshing()
        }
    }
    
    private func setDevices() {
        scannedDevices = BluetoothManager.shared.scannedDevices
            .filter { $0.isValid && (queryText.isEmpty || $0.name?.range(of: self.queryText, options: .caseInsensitive) != nil) }
    }
    
    private func reloadTableView() {
        self.tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
    }
    
    private func sortDevices() {
        scannedDevices = scannedDevices
            .filter { $0.isValid }
            .sorted {
                switch sortCriteria {
                case .alphabetically:
                    if $0.name == $1.name {
                        if $0.rssiBucket == $1.rssiBucket {
                            return $0.rssi > $1.rssi
                        }
                        return $0.rssiBucket > $1.rssiBucket
                    }
                    return $0.name ?? "ZZZZ" < $1.name ?? "ZZZZ"
                case .signalStrength:
                    if $0.rssiBucket == $1.rssiBucket {
                        if $0.name == $1.name {
                            return $0.rssi > $1.rssi
                        }
                        return $0.name ?? "ZZZZ" < $1.name ?? "ZZZZ"
                    } else {
                        return $0.rssiBucket > $1.rssiBucket
                    }
                }
            }
    }
}

extension AvailableDevicesViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return scannedDevices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "deviceCell", for: indexPath) as? AvailableDeviceTableViewCell
        else { return UITableViewCell() }
        let devices = scannedDevices
        cell.setState(devices[indexPath.row])
        return cell
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let devices = scannedDevices
        guard indexPath.row < devices.count else { return }
        (cell as? AvailableDeviceTableViewCell)?.setState(devices[indexPath.row])
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedDevice = scannedDevices[indexPath.row]
        performSegue(withIdentifier: "toConnectedDevice", sender: self)
    }
}

extension AvailableDevicesViewController: UISearchBarDelegate {
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        queryText = searchText
    }
}

extension AvailableDevicesViewController: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

extension AvailableDevicesViewController: BluetoothStateDelegate, PeripheralDelegate {
    
    func didScanAdvertisedData(for device: BluetoothDevice) {
        device.subscribeToPeripheralUpdates(self)
        var devices = self.scannedDevices
        devices = devices.filter({ self.queryText.isEmpty || $0.name?.range(of: self.queryText, options: .caseInsensitive) != nil })
        // Update actual value in scanned devices
        if let index = devices.firstIndex(where: { $0.uuid == device.uuid }) {
            let indexPath = IndexPath(row: index, section: 0)
            (self.tableView.cellForRow(at: indexPath) as? AvailableDeviceTableViewCell)?.setState(device)
        }
    }
    
    func didConnectToDevice(_ device: BluetoothDevice) {
        
    }
    
    func didDisconnectFromDevice(_ device: BluetoothDevice) {
        
    }
    
    func didDiscoverCharacteristics(for peripheral: CBPeripheral, characteristics: [CBCharacteristic], service: CBService) {
        
    }
    
    func didDiscoverServices(for peripheral: CBPeripheral, services: [CBService]) {
        
    }
    
    func didUpdateDescriptor(for peripheral: CBPeripheral, descriptor: CBDescriptor) {
        
    }
}

// MARK: - Keyboard
extension AvailableDevicesViewController {
    
    @objc func keyboardNotification(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue
            let keyboardIsDown = keyboardFrame.origin.y >= UIScreen.main.bounds.size.height
            let bottomConstraintConstant = keyboardIsDown ? 0 : keyboardFrame.size.height
            
            let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
            let animationCurveRawNSN = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber
            let animationCurveRaw = animationCurveRawNSN?.uintValue ?? UIView.AnimationOptions.curveEaseInOut.rawValue
            let animationCurve = UIView.AnimationOptions(rawValue: animationCurveRaw)

            UIView.animate(withDuration: duration, delay: 0, options: animationCurve, animations: {
                self.bottomConstraint.constant = bottomConstraintConstant
                self.view.layoutIfNeeded()
            }, completion: nil)
        }
    }
}

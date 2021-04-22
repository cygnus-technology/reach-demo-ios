//
//  ViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 3/8/21.
//  Copyright © 2021 Cygnus. All rights reserved.
//

import UIKit

fileprivate let SEARCH_BAR_BACKROUND_COLOR = UIColor(red: 0.94901960784, green: 0.94901960784, blue: 0.96862745098, alpha: 1.0)
fileprivate let SEARCH_BAR_TEXT_VIEW_COLOR = UIColor(red: 0.46274509803, green: 0.46274509803, blue: 0.50196078431, alpha: 0.12)

fileprivate enum DeviceSortCriteria {
    case alphabetically
    case signalStrength
}

class AvailableDevicesViewController: UIViewController {
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var sortButton: UIButton!
    
    fileprivate var sortCriteria = DeviceSortCriteria.signalStrength
    fileprivate var selectedDevice: BluetoothDevice?
    fileprivate var initialLoadComplete = false
    
    var scannedDevices = BluetoothManager.shared.scannedDevices
    var queryText = "" {
        didSet {
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        searchBar.delegate = self
        searchBar.textField?.delegate = self
        searchBar.backgroundImage = SEARCH_BAR_BACKROUND_COLOR.image(CGSize(width: searchBar.bounds.width, height: searchBar.bounds.height))
        searchBar.textField?.backgroundColor = SEARCH_BAR_TEXT_VIEW_COLOR
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.tableFooterView = UIView()
        tableView.refreshControl = UIRefreshControl()
        tableView.refreshControl?.addTarget(self, action: #selector(reloadDevices), for: .valueChanged)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.setNavigationBarHidden(true, animated: false)
        
        for indexPath in tableView.indexPathsForSelectedRows ?? [] {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        
        BluetoothManager.shared.subscribeToBluetoothState(self)
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
        
        BluetoothManager.shared.unsubscribeFromBluetoothState(self)
        BluetoothManager.shared.stopScanning()
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        return selectedDevice != nil
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "toConnectedDevice", let destinationVc = segue.destination as? SelectedDeviceViewController, let selectedDevice = self.selectedDevice {
            destinationVc.connectedDevice = selectedDevice
        }
    }
    
    @IBAction func accountButtonTapped(_ sender: Any) {
        performSegue(withIdentifier: "toAccount", sender: self)
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
    
    @objc private func reloadDevices() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { timer in
            self.scannedDevices = BluetoothManager.shared.scannedDevices
            self.sortDevices()
            self.reloadTableView()
            self.tableView.refreshControl?.endRefreshing()
        }
    }
    
    private func reloadTableView() {
        self.tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
    }
    
    private func sortDevices() {
        let now = Date().timeIntervalSince1970
        let devices = BluetoothManager.shared.scannedDevices.filter { now - $0.lastSeen < 30 }.sorted(by: {
            switch sortCriteria {
            case .alphabetically:
                return $0.name ?? "ZZZZ" < $1.name ?? "ZZZZ"
            case .signalStrength:
                return $0.RSSI > $1.RSSI
            }
        })
        
        self.scannedDevices = queryText.isEmpty ? devices : devices.filter({
            ($0.name ?? "Unknown").contains(queryText)
        })
    }
}

extension AvailableDevicesViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return scannedDevices.filter({ queryText.isEmpty || $0.name?.range(of: self.queryText, options: .caseInsensitive) != nil }).count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "deviceCell", for: indexPath) as? AvailableDeviceTableViewCell else { return UITableViewCell() }
        cell.setState(scannedDevices.filter({ queryText.isEmpty || $0.name?.range(of: self.queryText, options: .caseInsensitive) != nil })[indexPath.row])
        return cell
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        (cell as? AvailableDeviceTableViewCell)?.setState(scannedDevices.filter({ queryText.isEmpty || $0.name?.range(of: self.queryText, options: .caseInsensitive) != nil })[indexPath.row])
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.selectedDevice = self.scannedDevices.filter({ queryText.isEmpty || $0.name?.range(of: self.queryText, options: .caseInsensitive) != nil })[indexPath.row]
        self.performSegue(withIdentifier: "toConnectedDevice", sender: self)
    }
}

extension AvailableDevicesViewController: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        queryText = ""
        tableView.reloadData()
        searchBar.resignFirstResponder()
    }
    
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

extension AvailableDevicesViewController: BluetoothStateDelegate {
    var bluetoothStateDelegateId: String {
        return "AvailableDevicesViewController"
    }
    
    func didScanAdvertisedData(for device: BluetoothDevice) {
        DispatchQueue.main.async {
            var devices = self.scannedDevices
            devices = devices.filter({ self.queryText.isEmpty || $0.name?.range(of: self.queryText, options: .caseInsensitive) != nil })
            // Update actual value in scanned devices
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                let indexPath = IndexPath(row: index, section: 0)
                devices[index].updateDevice(with: device)
                (self.tableView.cellForRow(at: indexPath) as? AvailableDeviceTableViewCell)?.setState(device)
            }
        }
    }
    
    func didConnectToDevice(_ device: BluetoothDevice) {}

    func failedToConnectToDevice(_ device: BluetoothDevice) {}
    
    func didDisconnectFromDevice(_ device: BluetoothDevice) {}
    
    func bluetoothReset() {}
}

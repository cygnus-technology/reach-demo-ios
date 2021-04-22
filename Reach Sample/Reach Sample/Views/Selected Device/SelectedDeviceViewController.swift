//
//  SelectedDeviceViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 3/8/21.
//  Copyright © 2021 Cygnus. All rights reserved.
//

import UIKit
import CoreBluetooth
import PromiseKit

class SelectedDeviceViewController: UIViewController {
    @IBOutlet weak var loadingStackView: UIStackView?
    @IBOutlet weak var tableView: UITableView?
    @IBOutlet weak var continueButton: UIButton?
    
    private var valueText = ""
    private var reconnecting = false
    private var initialized = false
    
    var connectedDevice: BluetoothDevice!
    var characteristics = [CBService : [CBCharacteristic]]()
    
    private var _services = [CBService]()
    var services: [CBService] {
        return _services.sorted(by: {
            if $0.uuid.description != $0.uuid.uuidString && $1.uuid.description != $1.uuid.uuidString {
                return $0.uuid.description < $1.uuid.description
            } else if $0.uuid.description != $0.uuid.uuidString {
                return true
            } else if $1.uuid.description != $1.uuid.uuidString {
                return false
            } else {
                return $0.uuid.uuidString < $1.uuid.uuidString
            }
        })
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(reloadData), for: .valueChanged)
        tableView?.refreshControl = refresh
        tableView?.tableFooterView = UIView()
        
        title = connectedDevice.name ?? "Unnamed device"
        print("Attempting to connect to \(connectedDevice.name ?? connectedDevice.id.description)")

        connectedDevice.connect(withRetries: false).done {
            self.initialized = true
            self.loadingStackView?.isHidden = true
            self.tableView?.isHidden = false
            self.continueButton?.isHidden = false
        }.catch { error in
            if let btError = error as? BluetoothError, btError == .couldNotConnect {
                self.abort(message: btError.localizedDescription)
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        BluetoothManager.shared.subscribeToBluetoothState(self)
        connectedDevice.subscribeToPeripheralUpdates(self)
        navigationController?.setNavigationBarHidden(false, animated: true)
        
        if initialized {
            ProductService.shared.setRemoteSupportPin(nil)
            reconnect()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        BluetoothManager.shared.unsubscribeFromBluetoothState(self)
        connectedDevice.unsubscribeFromPeripheralUpdates(self)
        _services = []
        characteristics = [:]
        tableView?.reloadData()
        connectedDevice.disconnect()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "toSupportSetup", let destinationVc = segue.destination as? SetupSupportViewController {
            destinationVc.connectedDevice = self.connectedDevice
        }
    }
    
    @IBAction func connectButtonTapped(_ sender: Any) {
        performSegue(withIdentifier: "toSupportSetup", sender: self)
    }
    
    @objc func reloadData() {
        guard connectedDevice.isConnected else {
            self.tableView?.refreshControl?.endRefreshing()
            return
        }
        
        connectedDevice.peripheral.discoverServices(nil)
        
        var promises = [Promise<Void>]()
        for service in self.services {
            promises += self.characteristics[service]?.map { self.readCharacteristic($0) } ?? []
        }
        
        when(resolved: promises).done { _ in
            self.tableView?.refreshControl?.endRefreshing()
        }
    }
    
    @objc func reconnect() {
        let view = ReconnectingView()
        self.navigationItem.setRightBarButton(UIBarButtonItem(customView: view), animated: false)
        // Bug where activity indicator won't start animating right away no matter what
        after(seconds: 0.2).done {
            view.activityIndicator?.startAnimating()
        }
        self.reconnecting = true
        
        self.connectedDevice.connect(withRetries: false).done {
            print("Reconnected")
            self.navigationItem.rightBarButtonItem = nil
        }.catch { error in
            self.navigationItem.setRightBarButton(UIBarButtonItem(title: "Reconnect", style: .plain, target: self, action: #selector(self.reconnect)), animated: false)
            if let err = error as? BluetoothError, err == .connectionCancelled { return }
            self.showAlert(message: error.localizedDescription)
        }.finally {
            self.reconnecting = false
        }
    }
    
    private func abort(message: String) {
        showAlert(message: message) { action in
            self.navigationController?.popViewController(animated: true)
        }
    }
    
    private func readCharacteristic(_ characteristic: CBCharacteristic?) -> Promise<Void> {
        guard let char = characteristic, char.canRead else { return Promise() }
        let serviceId = characteristic?.service.uuid
        let (promise, seal) = Promise<Void>.pending()
        
        // IMPORTANT: Do not access the service in any callbacks by using characteristic.service. There is a chance it could be deallocated as it is an unowned (unsafe) variable. Instead safe the ID and look up the service manually in any callbacks
        connectedDevice.readValue(from: char).done { value in
            guard let charRef = characteristic, let service = self.connectedDevice.peripheral.services?.first(where: { $0.uuid == serviceId }) else { return }
            guard let section = self.services.firstIndex(of: service), let row = self.characteristics[service]?.firstIndex(of: charRef) else { return }
            let cell = self.tableView?.cellForRow(at: IndexPath(row: row, section: section + 1)) as? CharacteristicTableViewCell
            cell?.valueLabel.text = charRef.parsedTextValue
            cell?.setupLayout()
            seal.fulfill_()
        }.catch { error in
            print(error)
            seal.reject(error)
        }
        
        return promise
    }
}

extension SelectedDeviceViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        // Services plus a section for advertisement
        return services.count + 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return connectedDevice.advertisementData.count
        }
        
        return characteristics[services[section - 1]]?.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "characteristicCell", for: indexPath) as? CharacteristicTableViewCell else { return UITableViewCell() }
        
        var nameText: String? = ""
        var valueText: String? = ""
        
        if indexPath.section == 0 {
            let rawKey = Array(self.connectedDevice.advertisementData.keys)[indexPath.row]
            let rawData = "\(Array(self.connectedDevice.advertisementData.values)[indexPath.row])"
            let data = BluetoothManager.shared.parseAdvertisementData(key: rawKey, data: self.connectedDevice.advertisementData)
            
            cell.accessoryType = .none
            nameText = data?.key ?? rawKey
            valueText = data?.value ?? rawData
        } else if services.count > indexPath.section - 1, characteristics[services[indexPath.section - 1]]?.count ?? 0 > indexPath.row {
            let service = services[indexPath.section - 1]
            let characteristic = characteristics[service]?[indexPath.row]
            
            cell.accessoryType = characteristic?.canWrite ?? false ? .disclosureIndicator : .none
            nameText = characteristic?.name ?? characteristic?.uuid.uuidString
            valueText = characteristic?.parsedTextValue
        } else {
            print(indexPath)
            print(characteristics[services[indexPath.section - 1]]?.count.description ?? "nil")
        }
        
        cell.nameLabel.text = nameText
        cell.valueLabel.text = valueText
        cell.setupLayout()
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "Advertisement Data" : services[section - 1].uuid.description
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section > 0 else { return }
        let service = services[indexPath.section - 1]
        guard let characteristic = characteristics[service]?[indexPath.row], characteristic.canWrite else { return }
        
        let alert = UIAlertController(title: "Write Value to Characteristic", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Write", style: .default) { action in
            guard let data = self.valueText.data(using: .hex) else {
                self.showAlert(message: "Invalid value")
                return
            }
            
            self.connectedDevice.writeValue(data, characteristic: characteristic).done {}.catch { error in
                self.showAlert(message: error.localizedDescription)
            }
        })
        alert.addTextField { textField in
            textField.tag = 700
            textField.delegate = self
        }
        
        present(alert, animated: true, completion: nil)
    }
}

extension SelectedDeviceViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard textField.tag == 700 else { return true }
        valueText = (textField.text as NSString?)?.replacingCharacters(in: range, with: string) ?? ""
        return true
    }
}

extension SelectedDeviceViewController: BluetoothStateDelegate {
    
    var bluetoothStateDelegateId: String {
        return "SelectedDeviceViewController"
    }
    
    func didScanAdvertisedData(for device: BluetoothDevice) {
        DispatchQueue.main.async {
            guard device.id == self.connectedDevice.id else { return }
            self.connectedDevice.updateDevice(with: device)
            self.tableView?.reloadSections([0], with: .fade)
        }
    }
    
    func didDisconnectFromDevice(_ device: BluetoothDevice) {
        DispatchQueue.main.async {
            guard device.id == self.connectedDevice.id, self.initialized, !self.reconnecting else { return }
            
            let count = self.services.count
            self._services = []
            self.characteristics = [:]
            self.reconnect()
            self.tableView?.deleteSections(IndexSet(1...count), with: .fade)
        }
    }
    
    func didConnectToDevice(_ device: BluetoothDevice) {}
    func failedToConnectToDevice(_ device: BluetoothDevice) {}
    func bluetoothReset() {}
}

extension SelectedDeviceViewController: PeripheralDelegate {
    var peripheralDelegateId: String {
        return "SelectedDeviceViewController"
    }
    
    func didDiscoverServices(for peripheral: CBPeripheral, services: [CBService]) {
        DispatchQueue.main.async {
            guard peripheral.identifier == self.connectedDevice.id else { return }
            
            var newServices = [CBService]()
            for service in services {
                guard !self._services.contains(service) else { continue }
                self.characteristics[service] = []
                newServices.append(service)
            }
            
            self._services = services
            var sectionsToInsert = [Int]()
            for i in 0..<self.services.count {
                if newServices.contains(self.services[i]) {
                    sectionsToInsert.append(i + 1)
                }
            }
            
            if !sectionsToInsert.isEmpty {
                self.tableView?.reloadData()
            }
        }
    }
    
    func didDiscoverCharacteristics(for peripheral: CBPeripheral, characteristics: [CBCharacteristic], service: CBService) {
        DispatchQueue.main.async {
            guard peripheral.identifier == self.connectedDevice.id else { return }

            var foundNewCharacteristic = false
            for characteristic in characteristics {
                guard !(self.characteristics[service]?.contains(characteristic) ?? true) else { continue }
                
                foundNewCharacteristic = true
                self.characteristics[service]?.append(characteristic)
                self.readCharacteristic(characteristic).cauterize()
            }
            
            if foundNewCharacteristic, let section = self.services.firstIndex(of: service) {
                self.tableView?.reloadSections([section + 1], with: .automatic)
            }
        }
    }
    
    func didUpdateCharacteristic(for peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        let serviceId = characteristic.service.uuid
        
        DispatchQueue.main.async {
            guard peripheral.identifier == self.connectedDevice.id, let service = self.connectedDevice.peripheral.services?.first(where: { $0.uuid == serviceId }), let i = self.characteristics[service]?.firstIndex(of: characteristic) else { return }
            
            self.characteristics[service]?[i] = characteristic
        }
    }
    
    func didWriteToCharacteristic(for peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        let serviceId = characteristic.service.uuid
        
        DispatchQueue.main.async {
            guard peripheral.identifier == self.connectedDevice.id, let service = self.connectedDevice.peripheral.services?.first(where: { $0.uuid == serviceId }), let section = self.services.firstIndex(of: service), let row = self.characteristics[service]?.firstIndex(of: characteristic) else { return }
            (self.tableView?.cellForRow(at: IndexPath(row: row, section: section + 1)) as? CharacteristicTableViewCell)?.animateColorFlash(.green)
        }
    }
    
    func didUpdateDescriptor(for peripheral: CBPeripheral, descriptor: CBDescriptor) {
        let charId = descriptor.characteristic.uuid
        let serviceId = descriptor.characteristic.service.uuid
        
        DispatchQueue.main.async {
            guard peripheral.identifier == self.connectedDevice.id, let service = self.connectedDevice.peripheral.services?.first(where: { $0.uuid == serviceId }), let characteristic = self.connectedDevice.services[service]?.first(where: { $0.uuid == charId }), let section = self.services.firstIndex(of: service), let row = self.characteristics[service]?.firstIndex(of: characteristic) else { return }
            let cell = self.tableView?.cellForRow(at: IndexPath(row: row, section: section + 1)) as? CharacteristicTableViewCell
            cell?.nameLabel.text = characteristic.name ?? characteristic.uuid.uuidString
            cell?.setupLayout()
        }
    }
}

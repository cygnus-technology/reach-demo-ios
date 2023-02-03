//
//  SelectedDeviceViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 1/13/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import UIKit
import CoreBluetooth
import PromiseKit

class SelectedDeviceViewController: UIViewController {
    @IBOutlet weak var loadingStackView: UIStackView?
    @IBOutlet weak var tableView: UITableView?
    @IBOutlet weak var continueButton: UIButton?
    @IBOutlet weak var deviceStackView: UIStackView!
    @IBOutlet weak var continueView: UIView!
    
    private var valueText = ""
    private var reconnecting = false
    private var initialized = false
    
    /// User is trying to connect to a device from a support session
    var supportSessionConnect = false
    
    /// User is trying to view the device's characteristics from a support session
    var supportSessionParameters = false
    var peripheralDelegateId: String = "SelectedDeviceViewController"
    var bluetoothStateDelegateId: String = "SelectedDeviceViewController"
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
        
        continueView.isHidden = supportSessionConnect || supportSessionParameters
        
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(reloadData), for: .valueChanged)
        tableView?.refreshControl = refresh
        tableView?.tableFooterView = UIView()
        
        title = connectedDevice.name ?? "Unnamed device"
        print("Attempting to connect to \(connectedDevice.name ?? connectedDevice.uuid.uuidString)")
        
        if SupportService.shared.sessionActive {
            continueButton?.setTitle("BACK TO SESSION", for: .normal)
        }

        deviceStackView.isHidden = true
        connectedDevice.connect().done {
            SupportService.shared.selectedDevice = self.connectedDevice
            
            if self.supportSessionConnect {
                self.dismiss(animated: true)
            }
            
            self.initialized = true
            self.loadingStackView?.isHidden = true
            self.deviceStackView?.isHidden = false
        }.catch { error in
            self.abort(message: error.localizedDescription)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        connectedDevice.subscribeToPeripheralUpdates(self)
        
        if initialized {
            ProductService.shared.setRemoteSupportPin(nil)
            reconnect()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        connectedDevice.unsubscribeFromPeripheralUpdates(self)
        _services = []
        characteristics = [:]
        tableView?.reloadData()
        if !supportSessionConnect && !supportSessionParameters {
            SupportService.shared.disconnectDevice()
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "toSupportSetup", let destinationVc = segue.destination as? SetupSupportViewController {
            destinationVc.connectedDevice = self.connectedDevice
        }
    }
    
    @IBAction func connectButtonTapped(_ sender: Any) {
        supportSessionConnect = true
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
        navigationItem.setRightBarButton(UIBarButtonItem(customView: view), animated: false)
        // Bug where activity indicator won't start animating right away no matter what
        after(seconds: 0.2).done {
            view.activityIndicator?.startAnimating()
        }
        reconnecting = true
        
        connectedDevice.connect().done {
            print("Reconnected")
            self.navigationItem.rightBarButtonItem = nil
        }.catch { error in
            self.navigationItem.setRightBarButton(UIBarButtonItem(title: "Reconnect", style: .plain, target: self, action: #selector(self.reconnect)), animated: false)
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
        let service = characteristic?.service
        let (promise, seal) = Promise<Void>.pending()
        
        connectedDevice.readValue(from: char).done { value in
            guard let charRef = characteristic,
                  let service = service,
                  let section = self.services.firstIndex(of: service),
                  let row = self.characteristics[service]?.firstIndex(of: charRef)
            else { return }
            let cell = self.tableView?.cellForRow(at: IndexPath(row: row, section: section + 1)) as? CharacteristicTableViewCell
            if charRef.parsedTextValue == nil || charRef.parsedTextValue!.isEmpty {
                cell?.valueLabel.text = "- -"
            } else {
                cell?.valueLabel.text = charRef.parsedTextValue
            }
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
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "characteristicCell", for: indexPath) as? CharacteristicTableViewCell
        else { return UITableViewCell() }
        
        var nameText: String?
        var valueText: String?
        
        if indexPath.section == 0 {
            let rawKey = Array(connectedDevice.advertisementData.keys)[indexPath.row]
            let rawData = "\(Array(connectedDevice.advertisementData.values)[indexPath.row])"
            let data = BluetoothManager.shared.parseAdvertisementData(key: rawKey, data: connectedDevice.advertisementData)
            
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
        if valueText == nil || valueText!.isEmpty {
            cell.valueLabel.text = "- -"
        } else {
            cell.valueLabel.text = valueText
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return tableView.getHeaderLabel(title: ".", color: .white, backgroundColor: .white).bounds.height + 24
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let text = section == 0 ? "Advertisement Data" : services[section - 1].uuid.description.uppercased()
        return tableView.getHeaderLabel(title: text, color: Colors.primaryText.color, backgroundColor: Colors.raisedBackground.color)
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

extension SelectedDeviceViewController: BluetoothStateDelegate, PeripheralDelegate {
    
    func didScanAdvertisedData(for device: BluetoothDevice) {
        DispatchQueue.main.async {
            guard device.uuid == self.connectedDevice.uuid else { return }
            self.connectedDevice.updateDevice(with: device)
            self.tableView?.reloadSections([0], with: .fade)
        }
    }
    
    func didConnectToDevice(_ device: BluetoothDevice) {
        
    }
    
    func didDisconnectFromDevice(_ device: BluetoothDevice) {
        DispatchQueue.main.async {
            let count = self.services.count
            self._services = []
            self.characteristics = [:]
            self.reconnect()
            guard count >= 1 else { return }
            self.tableView?.deleteSections(IndexSet(1...count), with: .fade)
        }
    }
    
    func didDiscoverCharacteristics(for peripheral: CBPeripheral, characteristics: [CBCharacteristic], service: CBService) {
        DispatchQueue.main.async {
            var foundNewCharacteristic = false
            for characteristic in service.characteristics ?? [] {
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
    
    func didDiscoverServices(for peripheral: CBPeripheral, services: [CBService]) {
        DispatchQueue.main.async {
            var newServices = [CBService]()
            for service in self.connectedDevice.services.keys {
                guard !self._services.contains(service) else { continue }
                self.characteristics[service] = []
                newServices.append(service)
            }
            
            self._services = Array(self.connectedDevice.services.keys)
            var sectionsToInsert = [Int]()
            for i in 0..<self.connectedDevice.services.count {
                if newServices.contains(Array(self.connectedDevice.services.keys)[i]) {
                    sectionsToInsert.append(i + 1)
                }
            }
            
            if !sectionsToInsert.isEmpty {
                self.tableView?.reloadData()
            }
        }
    }
    
    func didUpdateDescriptor(for peripheral: CBPeripheral, descriptor: CBDescriptor) {
        let charId = descriptor.characteristic?.uuid
        let serviceId = descriptor.characteristic?.service?.uuid
        
        DispatchQueue.main.async {
            guard peripheral.identifier == self.connectedDevice.uuid,
                  let service = self.connectedDevice.peripheral.services?.first(where: { $0.uuid == serviceId }),
                  let characteristic = self.connectedDevice.services[service]?.first(where: { $0.uuid == charId }),
                  let section = self.services.firstIndex(of: service),
                  let row = self.characteristics[service]?.firstIndex(of: characteristic)
            else { return }
            let cell = self.tableView?.cellForRow(at: IndexPath(row: row, section: section + 1)) as? CharacteristicTableViewCell
            cell?.nameLabel.text = characteristic.name ?? characteristic.uuid.uuidString
        }
    }
    
    func didWriteToCharacteristic(for peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        let serviceId = characteristic.service?.uuid
        
        DispatchQueue.main.async {
            guard peripheral.identifier == self.connectedDevice.uuid,
                  let service = self.connectedDevice.peripheral.services?.first(where: { $0.uuid == serviceId }),
                  let section = self.services.firstIndex(of: service),
                  let row = self.characteristics[service]?.firstIndex(of: characteristic)
            else { return }
            (self.tableView?.cellForRow(at: IndexPath(row: row, section: section + 1)) as? CharacteristicTableViewCell)?.animateColorFlash(.green)
        }
    }
    
    func didUpdateCharacteristic(for peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        let serviceId = characteristic.service?.uuid
        
        DispatchQueue.main.async {
            guard peripheral.identifier == self.connectedDevice.uuid,
                  let service = self.connectedDevice.peripheral.services?.first(where: { $0.uuid == serviceId }),
                  let i = self.characteristics[service]?.firstIndex(of: characteristic)
            else { return }
            
            self.characteristics[service]?[i] = characteristic
        }
    }
}

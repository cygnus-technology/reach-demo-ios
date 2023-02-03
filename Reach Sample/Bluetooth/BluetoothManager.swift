//
//  BluetoothManager.swift
//  Reach Sample
//
//  Created by Cygnus on 3/8/21.
//  Copyright © 2021 Cygnus. All rights reserved.
//

import CoreBluetooth
import PromiseKit

protocol BluetoothStateDelegate {
    var bluetoothStateDelegateId: String { get }
    func didScanAdvertisedData(for device: BluetoothDevice)
    func didConnectToDevice(_ device: BluetoothDevice)
    func failedToConnectToDevice(_ device: BluetoothDevice)
    func didDisconnectFromDevice(_ device: BluetoothDevice)
    func bluetoothReset()
}

protocol PeripheralDelegate {
    var peripheralDelegateId: String { get }
    func didDiscoverCharacteristics(for peripheral: CBPeripheral, characteristics: [CBCharacteristic], service: CBService)
    func didDiscoverServices(for peripheral: CBPeripheral, services: [CBService])
    func didUpdateCharacteristic(for peripheral: CBPeripheral, characteristic: CBCharacteristic)
    func didUpdateDescriptor(for peripheral: CBPeripheral, descriptor: CBDescriptor)
    func didWriteToCharacteristic(for peripheral: CBPeripheral, characteristic: CBCharacteristic)
}

extension PeripheralDelegate {
    func failedToConnectToDevice(_ device: BluetoothDevice) {}
    func bluetoothReset() {}
    func didUpdateCharacteristic(for peripheral: CBPeripheral, characteristic: CBCharacteristic) {}
    func didWriteToCharacteristic(for peripheral: CBPeripheral, characteristic: CBCharacteristic) {}
}

class BluetoothManager: NSObject {
    static let shared = BluetoothManager()
    
    private var centralManager: CBCentralManager!
    private var bluetoothAuthorized = Promise<Void>.pending()
    private var connected = [UUID : (promise: Promise<Void>, resolver: Resolver<Void>)]()
    
    private let queue = DispatchQueue(label: "bleQueue", qos: .userInitiated)
    
    // Delegates to hook into bluetooth information
    private var stateDelegates = [BluetoothStateDelegate]()
    
    var scannedDevices: [BluetoothDevice] = []
    
    override init() {
        super.init()
        
        centralManager = CBCentralManager(delegate: self, queue: queue)
    }
    
    func subscribeToBluetoothState(_ delegate: BluetoothStateDelegate) {
        if !stateDelegates.contains(where: { $0.bluetoothStateDelegateId == delegate.bluetoothStateDelegateId }) {
            stateDelegates.append(delegate)
        }
    }
    
    func unsubscribeFromBluetoothState(_ delegate: BluetoothStateDelegate) {
        stateDelegates.removeAll(where: { $0.bluetoothStateDelegateId == delegate.bluetoothStateDelegateId })
    }
    
    /// Begins scanning for bluetooth devices once bluetooth is authorized
    func startScanning() -> Promise<Void> {
        return Promise { seal in
            bluetoothAuthorized.promise.done {
                print("Scanning for devices")
                self.centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
                seal.fulfill_()
            }.catch { error in
                seal.reject(error)
            }
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
    }
    
    /// Connects to device if device has been scanned. Returns true if device is scanned, false if not
    fileprivate func connectToDevice(_ device: BluetoothDevice) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        
        after(seconds: 10).done(on: queue) {
            guard promise.isPending else { return }
            print("Connection timeout")
            self.connected[device.uuid] = nil
            seal.reject(BluetoothError.couldNotConnect)
            self.centralManager.cancelPeripheralConnection(device.peripheral)
        }
        
        queue.async {
            self.connected[device.uuid] = (promise, seal)
            self.centralManager.connect(device.peripheral, options: nil)
        }
        
        return promise
    }
    
    fileprivate func disconnectFromDevice(_ device: BluetoothDevice) {
        centralManager.cancelPeripheralConnection(device.peripheral)
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("CBCentralManager's state is now \(central.state.description)")
        
        switch central.state {
        case .resetting:
            print("Resetting bluetooth")
            scannedDevices = []
            connected = [:]
            bluetoothAuthorized.resolver.reject(BluetoothError.resetting)
            bluetoothAuthorized = Promise<Void>.pending()
            stateDelegates.forEach({ $0.bluetoothReset() })
        case .unsupported:
            bluetoothAuthorized.resolver.reject(BluetoothError.unsupported)
        case .unauthorized:
            bluetoothAuthorized.resolver.reject(BluetoothError.notAuthorized)
        case .poweredOff:
            bluetoothAuthorized.resolver.reject(BluetoothError.poweredOff)
        case .poweredOn:
            bluetoothAuthorized.resolver.fulfill_()
            print("Bluetooth authorized")
        default:
            return
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let scannedDevice = BluetoothDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: Int(RSSI.intValue))
        var deviceExists = false
        for i in 0..<scannedDevices.count {
            if scannedDevices[i].uuid == scannedDevice.uuid {
                deviceExists = true
                scannedDevices[i].lastSeen = Date().timeIntervalSince1970
                scannedDevices[i].updateDevice(with: scannedDevice)
                break
            }
        }
        
        if !deviceExists {
            scannedDevices.append(scannedDevice)
        }
        
        stateDelegates.forEach({ $0.didScanAdvertisedData(for: scannedDevice) })
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let device = scannedDevices.first(where: { $0.uuid == peripheral.identifier }) else { return }
        print("Connected to device: \(device.name ?? device.uuid.uuidString)")
        
        stopScanning()
        
        peripheral.discoverServices(nil)
        
        device.stateChanged(.connected)
        self.stateDelegates.forEach({ $0.didConnectToDevice(device) })
        self.connected[device.uuid]?.resolver.fulfill_()
        self.connected[device.uuid] = nil
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to device: \(peripheral.name ?? "Nil")")
        guard let device = self.scannedDevices.first(where: { $0.uuid == peripheral.identifier }) else { return }
        
        self.stateDelegates.forEach({ $0.failedToConnectToDevice(device) })
        self.connected[device.uuid]?.resolver.reject(BluetoothError.couldNotConnect)
        self.connected[device.uuid] = nil
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let device = self.scannedDevices.first(where: { $0.uuid == peripheral.identifier }) else { return }
        print("Disconnected from device \(device.name ?? device.uuid.uuidString)")
        
        device.stateChanged(.disconnected)
        self.stateDelegates.forEach({ $0.didDisconnectFromDevice(device) })
        self.connected[device.uuid]?.resolver.reject(BluetoothError.connectionCancelled)
        self.connected[device.uuid] = nil
    }
}

extension BluetoothManager {
    
    /// Returns a human readable key and corresponding description of data based on the known advertisement dictionary keys
    func parseAdvertisementData(key: String, data: [String : Any]) -> (key: String, value: String?)? {
        switch key {
        case CBAdvertisementDataLocalNameKey:
            return (key: "Local Name", value: data[key] as? String)
        case CBAdvertisementDataIsConnectable:
            return (key: "Is Connectable", value: (data[key] as? Bool)?.description)
        case CBAdvertisementDataServiceDataKey:
            let value = data[key] as? [CBUUID : Data]
            let parsedValue = value?.mapValues { value in value.map { String(format: "%02hhx", $0) }.joined() }
            return (key: "Service Data", value: parsedValue?.description)
        case CBAdvertisementDataServiceUUIDsKey:
            return (key: "Service UUIDs", value: (data[key] as? [CBUUID])?.description)
        case CBAdvertisementDataTxPowerLevelKey:
            return (key: "Tx Power Level", value: (data[key] as? NSNumber)?.description)
        case CBAdvertisementDataManufacturerDataKey:
            let manufacturerData = data[key] as? Data
            var value: String?
            if let manData = manufacturerData, let dataString = String(data: manData, encoding: .utf8) {
                value = dataString
            } else {
                value = manufacturerData?.map { String(format: "%02hhx", $0) }.joined()
            }
            
            return (key: "Manufacturer Data", value: value)
        case CBAdvertisementDataOverflowServiceUUIDsKey, CBAdvertisementDataSolicitedServiceUUIDsKey:
            return (key: "Overflow Service UUIDs", value: (data[key] as? [CBUUID])?.description)
        case CBAdvertisementDataSolicitedServiceUUIDsKey:
            return (key: "Solicited Service UUIDs", value: (data[key] as? [CBUUID])?.description)
        default:
            return nil
        }
    }
}

// MARK: - Bluetooth Device
class BluetoothDevice: NSObject {
    var peripheral: CBPeripheral {
        didSet {
            peripheral.delegate = self
        }
    }
    
    var companyName: String?
    var lastSeen: TimeInterval
    var advertisementData: [String : Any]
    var rssi: Int
    var services: [CBService : [CBCharacteristic]] {
        var map = [CBService : [CBCharacteristic]]()
        peripheral.services?.forEach {
            map[$0] = $0.characteristics
        }
        
        return map
    }
    
    var uuid: UUID {
        return peripheral.identifier
    }
    
    var name: String? {
        return peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
    }
    
    var isConnected: Bool {
        return peripheral.state == .connected
    }
    
    var isValid: Bool {
        Date().timeIntervalSince1970 - lastSeen <= 30 && !uuid.uuidString.isEmpty
    }
    
    var servicesMap: [CBService : [CBCharacteristic]] {
        var map = [CBService : [CBCharacteristic]]()
        peripheral.services?.forEach {
            map[$0] = $0.characteristics
        }
        
        return map
    }
    
    var rssiBucket: Int {
        get {
            switch rssi {
            case -84 ... -60:
                return 1
            case -59 ... -40:
                return 2
            case -39 ... 0:
                return 3
            default:
                return 0
            }
        }
    }
    
    private var reconnecting = false
    private var peripheralDelegates = [PeripheralDelegate]()
    private var readMap = [String : [Resolver<Data>]]()
    private var writeMap = [String : [Resolver<Void>]]()
    private var notifyMap = [String : [Resolver<Void>]]()
    
    init(peripheral: CBPeripheral, advertisementData: [String : Any], rssi: Int) {
        self.peripheral = peripheral
        self.advertisementData = advertisementData
        self.rssi = rssi
        self.lastSeen = Date().timeIntervalSince1970
        super.init()
        self.peripheral.delegate = self
    }
    
    func subscribeToPeripheralUpdates(_ delegate: PeripheralDelegate) {
        if !peripheralDelegates.contains(where: { $0.peripheralDelegateId == delegate.peripheralDelegateId }) {
            peripheralDelegates.append(delegate)
        }
    }
    
    func unsubscribeFromPeripheralUpdates(_ delegate: PeripheralDelegate) {
        peripheralDelegates.removeAll(where: { $0.peripheralDelegateId == delegate.peripheralDelegateId })
    }
    
    func getCharacteristic(uuid: String) -> CBCharacteristic? {
        let characteristics = peripheral.services?.flatMap { $0.characteristics ?? [] } ?? []
        return characteristics.first(where: { $0.uuid == CBUUID(string: uuid) })
    }
    
    func connect(withRetries: Bool = true) -> Promise<Void> {
        reconnecting = true
        let promise = attempt(maximumRetryCount: withRetries ? 3 : 0) {
            return self.reconnecting ? BluetoothManager.shared.connectToDevice(self) : Promise()
        }
        
        promise.ensure {
            self.reconnecting = false
        }.cauterize()
        
        return promise
    }
    
    func disconnect() {
        reconnecting = false
        BluetoothManager.shared.disconnectFromDevice(self)
    }
    
    func setNotify(characteristic: CBCharacteristic, notify: Bool) -> Promise<Void> {
        guard isConnected else { return Promise(error: NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey : "Device is not connected"])) }
        guard characteristic.canNotify else { return Promise(error: NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey : "Characteristic does not have ability to notify"])) }
        let (promise, seal) = Promise<Void>.pending()
        let uuid = characteristic.uuid.uuidString
        self.notifyMap[uuid] = (self.notifyMap[uuid] ?? []) + [seal]
        self.peripheral.setNotifyValue(notify, for: characteristic)
        return promise
    }
    
    func readValue(from characteristic: CBCharacteristic) -> Promise<Data> {
        guard isConnected else {
            return Promise(error: NSError(domain: "BluetoothDevice", code: 0, userInfo: [NSLocalizedDescriptionKey : "Cannot read from characteristic when not connected"]))
        }
        guard characteristic.canRead else {
            return Promise(error: NSError(domain: "BluetoothDevice", code: 0, userInfo: [NSLocalizedDescriptionKey : "Characteristic \(characteristic.uuid) does not allow read operations."]))
        }
        
        let (promise, seal) = Promise<Data>.pending()
        
        after(seconds: 5).done {
            guard promise.isPending, self.readMap[self.uuid.uuidString]?.first != nil else { return }
            self.readMap[self.uuid.uuidString]?.removeFirst()
            seal.reject(BluetoothError.readTimeout)
        }
        
        self.readMap[characteristic.uuid.uuidString] = (self.readMap[characteristic.uuid.uuidString] ?? []) + [seal]
        self.peripheral.readValue(for: characteristic)
        
        return promise
    }
    
    func writeValue(_ value: Data, characteristic: CBCharacteristic) -> Promise<Void> {
        guard isConnected else {
            return Promise(error: NSError(domain: "BluetoothDevice", code: 0, userInfo: [NSLocalizedDescriptionKey : "Cannot write to characteristic when not connected"]))
        }
        guard characteristic.canWrite else {
            return Promise(error: NSError(domain: "BluetoothDevice", code: 0, userInfo: [NSLocalizedDescriptionKey : "Characteristic \(characteristic.uuid) does not allow write operations."]))
        }
        
        let (promise, seal) = Promise<Void>.pending()
        
        after(seconds: 5).done {
            guard promise.isPending, self.writeMap[self.uuid.uuidString]?.first != nil else { return }
            self.writeMap[self.uuid.uuidString]?.removeFirst()
            seal.reject(BluetoothError.writeTimeout)
        }
        
        self.writeMap[characteristic.uuid.uuidString] = (self.writeMap[characteristic.uuid.uuidString] ?? []) + [seal]
        self.peripheral.writeValue(value, for: characteristic, type: .withResponse)
        
        return promise
    }
    
    /// Get a JSON structured description of this device
    func getDeviceData() -> DeviceData {
        return DeviceData(
            localName: name ?? "Unnamed",
            macAddress: uuid.uuidString,
            rssi: rssi,
            signalStrength: rssiBucket,
            advertisementData: getAdvertisementInfo(),
            services: servicesMap.map { service, characteristics in
                ServiceInfo(
                    uuid: service.uuid.uuidString,
                    characteristics: getCharacteristicInfo(for: service)
                )
            }
        )
    }
    
    /// Get a JSON structured description of this device
    func getDiagnostics() -> [String : Any] {
        var diagnostics: [String : Any] = [
            "localName" : name ?? "Unnamed",
            "advertisementData" : self.getAdvertisementInfo()
        ]
        
        var servicesJson = [[String : Any]]()
        for service in services {
            var serviceJson: [String : Any] = [
                "uuid" : service.key.uuid.uuidString,
                "characteristics" : self.getCharacteristicInfo(for: service.key)
            ]
            
            if service.key.uuid.description != service.key.uuid.uuidString {
                serviceJson["name"] = service.key.uuid.description
            }
            
            servicesJson.append(serviceJson)
        }
        
        diagnostics["services"] = servicesJson
        
        return diagnostics
    }
    
    func updateDevice(with device: BluetoothDevice) {
        guard device.uuid == self.uuid else { return }
        self.peripheral = device.peripheral
        
        if abs(device.rssi - rssi) >= 5 {
            self.rssi = device.rssi
        }
    }
}

extension BluetoothDevice {
    
    fileprivate func stateChanged(_ state: CBPeripheralState) {
        if state == .disconnected {
            self.readMap.forEach { char in char.value.forEach { $0.reject(BluetoothError.noConnectedDevice) }}
            self.writeMap.forEach { char in char.value.forEach { $0.reject(BluetoothError.noConnectedDevice) }}
            self.readMap = [:]
            self.writeMap = [:]
        }
    }
    
    /// This must be used to get advertisement info for usage as JSON in order to get rid of any NSObjects
    private func getAdvertisementInfo() -> [String : String] {
        var advertisementJson = [String : String]()
        advertisementData.forEach {
            if let parsed = BluetoothManager.shared.parseAdvertisementData(key: $0.key, data: advertisementData),
               let value = parsed.value
            {
                advertisementJson[parsed.key] = value
            } else {
                advertisementJson[$0.key] = "\($0.value)"
            }
        }
        
        return advertisementJson
    }
    
    private func getCharacteristicInfo(for service: CBService) -> [CharacteristicInfo] {
        let characteristics = servicesMap[service] ?? []
        return characteristics.map { characteristic in
            var value: String?
            var encoding: BluetoothEncoding?
            
            if let data = characteristic.value {
                let decoded = String(data: data, encoding: .utf8)
                encoding = decoded == nil ? .hex : .utf8
                value = decoded ?? data.map { String(format: "%02hhx", $0) }.joined()
            }
            
            return CharacteristicInfo(
                uuid: characteristic.uuid.uuidString,
                read: characteristic.canRead,
                write: characteristic.canWrite,
                notify: characteristic.canNotify,
                name: characteristic.name,
                value: value,
                encoding: encoding
            )
        }
    }
}

extension BluetoothDevice: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            print("Discovered service \(service.uuid)")
            guard isConnected else { continue }
            peripheral.discoverCharacteristics(nil, for: service)
        }
        
        peripheralDelegates.forEach({ $0.didDiscoverServices(for: peripheral, services: services) })
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            print("Discovered characteristic: \(characteristic.uuid)")
            guard isConnected else { continue }
            peripheral.discoverDescriptors(for: characteristic)
        }
        
        peripheralDelegates.forEach({ $0.didDiscoverCharacteristics(for: peripheral, characteristics: characteristics, service: service) })
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        for descriptor in characteristic.descriptors ?? [] {
            guard isConnected else { continue }
            peripheral.readValue(for: descriptor)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        peripheralDelegates.forEach({ $0.didUpdateDescriptor(for: peripheral, descriptor: descriptor) })
        
        switch descriptor.uuid.uuidString {
        case CBUUIDCharacteristicUserDescriptionString:
            guard let description = descriptor.value as? String else {
                break
            }
            print("User description: \(description)")
        case CBUUIDCharacteristicFormatString:
            guard let format = descriptor.value as? Data else {
                break
            }
            print("Format: \(format)")
        default:
            break
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Failed to update value for characteristic \(characteristic.uuid): " + error.localizedDescription)
            if let resolver = self.writeMap[characteristic.uuid.uuidString]?.first {
                resolver.reject(error)
                self.writeMap[characteristic.uuid.uuidString]?.removeFirst()
            }
        } else {
            print("Wrote value for characteristic \(characteristic.uuid.uuidString)")
            if let resolver = self.writeMap[characteristic.uuid.uuidString]?.first {
                resolver.fulfill_()
                self.writeMap[characteristic.uuid.uuidString]?.removeFirst()
            }
        }
        
        self.peripheralDelegates.forEach({ $0.didWriteToCharacteristic(for: peripheral, characteristic: characteristic) })
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Failed to update value for characteristic \(characteristic.uuid): " + error.localizedDescription)
            if let resolver = self.readMap[characteristic.uuid.uuidString]?.first {
                resolver.reject(error)
                self.readMap[characteristic.uuid.uuidString]?.removeFirst()
            }
        } else if let value = characteristic.value {
            print("Updated value for characteristic \(characteristic.uuid)")
            if let resolver = self.readMap[characteristic.uuid.uuidString]?.first {
                resolver.fulfill(value)
                self.readMap[characteristic.uuid.uuidString]?.removeFirst()
            }
        }
        
        self.peripheralDelegates.forEach({ $0.didUpdateCharacteristic(for: peripheral, characteristic: characteristic) })
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid.uuidString
        if let error = error {
            if let seal = self.notifyMap[uuid]?.first {
                seal.reject(error)
                self.notifyMap[uuid]?.removeFirst()
            }
        } else {
            if let seal = self.notifyMap[uuid]?.first {
                seal.fulfill_()
                self.notifyMap[uuid]?.removeFirst()
            }
        }
    }
}

// MARK: - CoreBluetooth extensions
extension CBCharacteristic {
    var name: String? {
        return uuid.description != uuid.uuidString ? uuid.description : descriptors?.first(where: { $0.uuid.uuidString == CBUUIDCharacteristicUserDescriptionString })?.value as? String
    }
    
    var canRead: Bool {
        return properties.contains(CBCharacteristicProperties.read)
    }
    
    var canWrite: Bool {
        return properties.contains(CBCharacteristicProperties.write)
    }
    
    var canNotify: Bool {
        return properties.contains(CBCharacteristicProperties.notify)
    }
    
    var parsedTextValue: String? {
        guard let value = value else { return nil }
        
        if let formattedString = self.formattedString {
            return formattedString
        }
        
        let utf8String = String(data: value, encoding: .utf8)
        return (utf8String != nil && uuid.uuidString != uuid.description) ? utf8String : value.map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// String description of whatever the characteristic's value is based off of the Presentation Format descriptor
    private var formattedString: String? {
        guard let data = value,
            let formatData = descriptors?.first(where: { $0.uuid.uuidString == CBUUIDCharacteristicFormatString })?.value as? Data,
            let formatByte = UInt8(data: formatData.subdata(in: 0..<1)),
            let exponent = Int8(data: formatData.subdata(in: 1..<2)),
            let unitBytes = UInt16(data: formatData.subdata(in: 2..<4))?.bigEndian,
            let format = CharacteristicFormat(rawValue: formatByte) else { return nil }
        
        var formatString = ""
        
        switch format {
        case .bool:
            return Bool(data: data)?.description
        case .uint8:
            guard let val = UInt8(data: data) else { return nil }
            let actualVal = Double(val) * pow(10.0, Double(exponent))
            formatString = actualVal.description
        case .uint16:
            guard let val = UInt16(data: data) else { return nil }
            let actualVal = Double(val) * pow(10.0, Double(exponent))
            formatString = actualVal.description
        case .uint32:
            guard let val = UInt32(data: data) else { return nil }
            let actualVal = Double(val) * pow(10.0, Double(exponent))
            formatString = actualVal.description
        case .uint64:
            guard let val = UInt64(data: data) else { return nil }
            let actualVal = Double(val) * pow(10.0, Double(exponent))
            formatString = actualVal.description
        case .int8:
            guard let val = Int8(data: data) else { return nil }
            let actualVal = Double(val) * pow(10.0, Double(exponent))
            formatString = actualVal.description
        case .int16:
            guard let val = Int16(data: data) else { return nil }
            let actualVal = Double(val) * pow(10.0, Double(exponent))
            formatString = actualVal.description
        case .int32:
            guard let val = Int32(data: data) else { return nil }
            let actualVal = Double(val) * pow(10.0, Double(exponent))
            formatString = actualVal.description
        case .int64:
            guard let val = Int64(data: data) else { return nil }
            let actualVal = Double(val) * pow(10.0, Double(exponent))
            formatString = actualVal.description
        case .float32:
            guard let val = Float32(data: data) else { return nil }
            let actualVal = Double(val) * pow(10.0, Double(exponent))
            formatString = actualVal.description
        case .float64:
            guard let val = Float64(data: data) else { return nil }
            let actualVal = Double(val) * pow(10.0, Double(exponent))
            formatString = actualVal.description
        }
        
        if let unit = CBCharacteristic.unitDefinitions[unitBytes] {
            formatString += " \(unit)"
        }
        
        return formatString
    }
    
    enum CharacteristicFormat: UInt8 {
        case bool = 1
        case uint8 = 4
        case uint16 = 6
        case uint32 = 8
        case uint64 = 10
        case int8 = 12
        case int16 = 14
        case int32 = 16
        case int64 = 18
        case float32 = 20
        case float64 = 21
    }
    
    static var unitDefinitions: [UInt16: String] = [0x2700:"",0x2701:"Meters",0x2702:"Kilograms",0x2703:"Seconds",0x2704:"Amperes",0x2705:"K",0x2706:"Moles",0x2707:"Candelas",0x2710:"m2",0x2711:"m3",0x2712:"m/s",0x2713:"m/s2",0x2714:"Wavenumber",0x2715:"kg/m3",0x2716:"kg/m2",0x2717:"m3/kg",0x2718:"A/m2",0x2719:"A/m",0x271A:"mol/m3",0x271B:"kg/m3",0x271C:"cd/m2",0x271D:"n",0x271E:"Kri",0x2720:"Radians",0x2721:"Steradians",0x2722:"Hz",0x2723:"N",0x2724:"Pa",0x2725:"Joules",0x2726:"Watts",0x2727:"Coulombs",0x2728:"Volts",0x2729:"Farads",0x272A:"Ohms",0x272B:"Siemens",0x272C:"Webers",0x272D:"Teslas",0x272E:"H",0x272F:"C",0x2730:"Lumens",0x2731:"Lux",0x2732:"Bq",0x2733:"Gy",0x2734:"Sv",0x2735:"kat",0x2740:"Pa/s",0x2741:"Nm",0x2742:"N/m",0x2743:"rad/s",0x2744:"rad/s2",0x2745:"W/m2)",0x2746:"J/K0",0x2747:"J/kgK",0x2748:"J/kg",0x2749:"W/(mK)",0x274A:"J/m3",0x274B:"V/m",0x274C:"Coulomb/m3",0x274D:"Coulomb/m2",0x274E:"Coulomb/m2",0x274F:"Farad/m",0x2750:"H/m",0x2751:"Joule/mole",0x2752:"J/molK",0x2753:"Coulomb/kg",0x2754:"Gy/s",0x2755:"W/sr",0x2756:"W/m2sr",0x2757:"Katal/m3",0x2760:"Minutes",0x2761:"Hours",0x2762:"Days",0x2763:"Degrees",0x2764:"Minutes",0x2765:"Seconds",0x2766:"Hectares",0x2767:"Litres",0x2768:"Tonnes",0x2780:"bar",0x2781:"mmHg",0x2782:"Angstroms",0x2783:"NM",0x2784:"Barns",0x2785:"Knots",0x2786:"Nepers",0x2787:"bel",0x27A0:"Yards",0x27A1:"Parsecs",0x27A2:"Inches",0x27A3:"Feet",0x27A4:"Miles",0x27A5:"psi",0x27A6:"KPH",0x27A7:"MPH",0x27A8:"RPM",0x27A9:"cal",0x27AA:"Cal",0x27AB:"kWh",0x27AC:"F",0x27AD:"Percent",0x27AE:"Per Mile",0x27AF:"bp/m",0x27B0:"Ah",0x27B1:"mg/Decilitre",0x27B2:"mmol/l",0x27B3:"Years",0x27B4:"Months",0x27B5:"Count/m3",0x27B6:"Watt/m2",0x27B7:"ml/kg/min",0x27B8:"lbs"]
}

extension CBManagerState {
    var description: String {
        switch self {
        case .unknown:
            return "unknown"
        case .resetting:
            return "resetting"
        case .unsupported:
            return "unsupported"
        case .unauthorized:
            return "unauthorized"
        case .poweredOff:
            return "poweredOff"
        case .poweredOn:
            return "poweredOn"
        @unknown default:
            return "unkown"
        }
    }
}

enum BluetoothError: LocalizedError {
    case notAuthorized
    case unsupported
    case poweredOff
    case resetting
    case noConnectedDevice
    case couldNotConnect
    case connectionCancelled
    case readTimeout
    case writeTimeout
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Bluetooth must be authorized"
        case .unsupported:
            return "Bluetooth is not supported on this device"
        case .poweredOff:
            return "Device's bluetooth must be turned on"
        case .resetting:
            return "Resetting bluetooth"
        case .noConnectedDevice:
            return "Cannot perform operation because there is no connected device"
        case .couldNotConnect:
            return "Could not connect to device"
        case .connectionCancelled:
            return "Connection attempt was cancelled"
        case .readTimeout:
            return "Reading characteristic timed out"
        case .writeTimeout:
            return "Writing to characteristic timed out"
        }
    }
}

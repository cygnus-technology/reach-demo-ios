//
//  Extensions.swift
//  Reach Sample
//
//  Created by Cygnus on 3/8/21.
//  Copyright © 2021 Cygnus. All rights reserved.
//

import UIKit
import PromiseKit
import MobileCoreServices

extension UIViewController {
    /// Sets up a notification to dismiss the keyboard if a user taps off of it
    func setupTapToDismissKeyboard() {
        let tap: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(UIViewController.dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }
    
    @objc func dismissKeyboard() {
        view.endEditing(true)
    }
    
    func showAlert(title: String? = nil, message: String?, buttonTitle: String = "Ok", action: ((UIAlertAction) -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: buttonTitle, style: .default, handler: action))
        present(alert, animated: true, completion: nil)
    }
}

extension UIColor {
    
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        var hexInt: UInt64 = 0
        let scanner: Scanner = Scanner(string: hex)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "#")
        scanner.scanHexInt64(&hexInt)
        
        let red = CGFloat((hexInt & 0xff0000) >> 16) / 255.0
        let green = CGFloat((hexInt & 0xff00) >> 8) / 255.0
        let blue = CGFloat((hexInt & 0xff) >> 0) / 255.0
        
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    func image(_ size: CGSize = CGSize(width: 1, height: 1)) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { rendererContext in
            self.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: size))
        }
    }
}

/// Promise extension for retries and delay between retries
func attempt<T>(maximumRetryCount: Int = 3, delayBeforeRetry: DispatchTimeInterval = .seconds(0), _ body: @escaping () -> Promise<T>) -> Promise<T> {
    var attempts = 0

    func attempt() -> Promise<T> {
        attempts += 1

        return body().recover { error -> Promise<T> in
            guard attempts < maximumRetryCount else { throw error }

            return after(delayBeforeRetry).then(on: nil, attempt)
        }
    }

    return attempt()
}

extension UIView {
    @IBInspectable var borderColor: UIColor? {
        get {
            return UIColor(cgColor: layer.borderColor!)
        } set {
            layer.borderColor = newValue?.cgColor
        }
    }
}

extension UIButton {
    
    // Uses native setBackgroundImage to set a background color for a given state
    func setBackgroundColor(_ color: UIColor, forState: UIControl.State) {
        let minimumSize: CGSize = CGSize(width: 1.0, height: 1.0)
        UIGraphicsBeginImageContext(minimumSize)
        
        if let context = UIGraphicsGetCurrentContext() {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(origin: .zero, size: minimumSize))
        }
        
        let colorImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        self.clipsToBounds = true
        self.setBackgroundImage(colorImage, for: forState)
    }
}

extension URL {
    var mimeType: String {
        let pathExtension = self.pathExtension
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension as NSString, nil)?.takeRetainedValue() {
            if let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                return mimetype as String
            }
        }
        return "application/octet-stream"
    }
}

extension Data {
    func writeMp4DataToLocalUrl(with fileName: String) -> Promise<URL> {
        return Promise { seal in
            DispatchQueue.global().async {
                var name = fileName
                if !name.hasSuffix(".mp4") {
                    name += ".mp4"
                }
                
                do {
                    let url = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent(name)
                    try self.write(to: url)
                    seal.fulfill(url)
                } catch {
                    seal.reject(error)
                }
            }
        }
    }
}

extension String {
    enum ExtendedEncoding {
        case hex
    }

    /// Gets the binary representation of a hex string. Pads with 0s if necessary
    func data(using encoding: ExtendedEncoding) -> Data? {
        var hexStr = self.dropFirst(self.hasPrefix("0x") ? 2 : 0)
        
        // Pad uneven hex string with 0s
        if hexStr.count % 2 == 1 {
            hexStr = "0" + hexStr
        }
        
        var newData = Data(capacity: hexStr.count / 2)

        var indexIsEven = true
        for i in hexStr.indices {
            if indexIsEven {
                let byteRange = i...hexStr.index(after: i)
                guard let byte = UInt8(hexStr[byteRange], radix: 16) else { return nil }
                newData.append(byte)
            }
            
            indexIsEven.toggle()
        }
        
        return newData
    }
}

protocol DataConvertible {
    init?(data: Data)
    var data: Data { get }
}

extension DataConvertible where Self: ExpressibleByIntegerLiteral{
    init?(data: Data) {
        var value: Self = 0
        guard data.count == MemoryLayout.size(ofValue: value) else { return nil }
        _ = withUnsafeMutableBytes(of: &value, { data.copyBytes(to: $0)} )
        self = value
    }

    var data: Data {
        return withUnsafeBytes(of: self) { Data($0) }
    }
}

extension UInt8: DataConvertible {}
extension UInt16: DataConvertible {}
extension UInt32: DataConvertible {}
extension UInt64: DataConvertible {}
extension Int8: DataConvertible {}
extension Int16: DataConvertible {}
extension Int32: DataConvertible {}
extension Int64: DataConvertible {}
extension Float32: DataConvertible {}
extension Float64: DataConvertible {}
extension Bool: DataConvertible {
    init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count == 1 else { return nil }
        self.init(bytes[0] == 1)
    }
    
    var data: Data {
        return Data(repeating: self ? 1 : 0, count: 1)
    }
}

extension UISearchBar {
    var textField : UITextField? {
        if #available(iOS 13.0, *) {
            return self.searchTextField
        } else {
            guard self.subviews.count > 0 else { return nil }
            return self.subviews[0].subviews.compactMap { $0 as? UITextField }.first
        }
    }
}

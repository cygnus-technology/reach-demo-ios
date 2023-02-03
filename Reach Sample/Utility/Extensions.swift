//
//  Extensions.swift
//  Reach Sample
//
//  Created by Cygnus on 1/13/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import UIKit
import PromiseKit
import MobileCoreServices

extension UIViewController {
    
    var windowInterfaceOrientation: UIInterfaceOrientation? {
        return UIApplication.shared.windows.first?.windowScene?.interfaceOrientation
    }
    
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
    
    func showToast(message: String) {
        let toastHeight: CGFloat = 50
        let toastMargin: CGFloat = 16
        let toastWidth = view.bounds.width - (toastMargin * 2)
        let visibleY = view.bounds.height - toastMargin - 1 - toastHeight
        let toast = UIView(frame: CGRect(x: toastMargin, y: view.bounds.height, width: toastWidth, height: toastHeight))
        toast.tag = 999
        toast.backgroundColor = .black
        toast.layer.cornerRadius = 4
        toast.layer.shadowColor = UIColor.black.withAlphaComponent(0.5).cgColor
        toast.layer.shadowOffset = CGSize(width: 0, height: 6)
        toast.layer.shadowRadius = 8
        toast.layer.shadowOpacity = 1
        
        let cancelButton = UIButton()
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        cancelButton.addTarget(self, action: #selector(hideToast), for: .touchUpInside)
        cancelButton.tintColor = .white
        toast.addSubview(cancelButton)
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.text = message
        toast.addSubview(titleLabel)
        let titleConstraints = [
            NSLayoutConstraint(item: titleLabel, attribute: .centerY, relatedBy: .equal, toItem: toast, attribute: .centerY, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: titleLabel, attribute: .leading, relatedBy: .equal, toItem: cancelButton, attribute: .trailing, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: titleLabel, attribute: .trailing, relatedBy: .equal, toItem: toast, attribute: .trailing, multiplier: 1, constant: -16)
        ]
        let cancelConstraints = [
            NSLayoutConstraint(item: cancelButton, attribute: .height, relatedBy: .equal, toItem: toast, attribute: .height, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: cancelButton, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 52),
            NSLayoutConstraint(item: cancelButton, attribute: .leading, relatedBy: .equal, toItem: toast, attribute: .leading, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: cancelButton, attribute: .centerY, relatedBy: .equal, toItem: toast, attribute: .centerY, multiplier: 1, constant: 0)
        ]
        
        toast.addConstraints(titleConstraints + cancelConstraints)
        self.view.addSubview(toast)
        
        UIView.animate(withDuration: 0.1, delay: 0, options: .transitionCurlUp, animations: {
            toast.frame = CGRect(x: toastMargin, y: visibleY, width: toastWidth, height: toastHeight)
        }, completion: { success in
            Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { timer in
                self.hideToast()
            }
        })
    }
    
    @objc func hideToast() {
        guard let toast = self.view.subviews.first(where: { $0.tag == 999 }) else { return }
        
        UIView.animate(withDuration: 0.1, delay: 0, options: .transitionCurlDown, animations: {
            toast.frame = CGRect(x: toast.frame.minX, y: toast.frame.minY + toast.bounds.height + 17, width: toast.frame.width, height: toast.frame.height)
        }, completion: { success in
            toast.removeFromSuperview()
        })
    }
    
    func setupClearNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowImage = UIImage()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
    }
}

extension UIAlertController {
    
    static func showAlert(_ alert: UIAlertController) {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
        let delegate = scene?.delegate as? UIWindowSceneDelegate
        let root = delegate?.window??.rootViewController
        
        var presented = root
        while presented?.presentedViewController != nil {
            presented = presented?.presentedViewController
        }
        presented?.present(alert, animated: true)
    }
    
    static func showAlert(
        title: String? = nil,
        message: String?,
        buttonTitle: String = "Ok",
        action: ((UIAlertAction) -> Void)? = nil
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: buttonTitle, style: .default, handler: action))
        showAlert(alert)
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
    
    func image(_ size: CGSize = CGSize(width: 1, height: 1), cornerRadius: CGFloat = 0) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { rendererContext in
            self.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: size))
        }
    }
}

extension UIImage {
    
    func rounded(radius: CGFloat) -> UIImage {
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
        draw(in: rect)
        return UIGraphicsGetImageFromCurrentImageContext()!
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
    
    enum Border {
        case top
        case right
        case bottom
        case left
    }
    
    func addBorder(_ side: Border, color: UIColor, width: CGFloat) {
        switch side {
        case .top:
            addTopBorder(with: color, width: width)
        case .right:
            addRightBorder(with: color, width: width)
        case .bottom:
            addBottomBorder(with: color, width: width)
        case .left:
            addLeftBorder(with: color, width: width)
        }
    }
    
    private func addTopBorder(with color: UIColor?, width: CGFloat) {
        let border = UIView()
        border.backgroundColor = color
        border.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        border.frame = CGRect(x: 0, y: 0, width: frame.size.width, height: width)
        addSubview(border)
    }

    private func addBottomBorder(with color: UIColor?, width: CGFloat) {
        let border = UIView()
        border.backgroundColor = color
        border.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        border.frame = CGRect(x: 0, y: frame.size.height - width, width: frame.size.width, height: width)
        addSubview(border)
    }

    private func addLeftBorder(with color: UIColor?, width: CGFloat) {
        let border = UIView()
        border.backgroundColor = color
        border.frame = CGRect(x: 0, y: 0, width: width, height: frame.size.height)
        border.autoresizingMask = [.flexibleHeight, .flexibleRightMargin]
        addSubview(border)
    }

    private func addRightBorder(with color: UIColor?, width: CGFloat) {
        let border = UIView()
        border.backgroundColor = color
        border.autoresizingMask = [.flexibleHeight, .flexibleLeftMargin]
        border.frame = CGRect(x: frame.size.width - width, y: 0, width: width, height: frame.size.height)
        addSubview(border)
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

extension UITextField {

    enum PaddingSide {
        case left(CGFloat)
        case right(CGFloat)
        case both(CGFloat)
    }

    func addPadding(_ padding: PaddingSide) {
        leftViewMode = .always
        layer.masksToBounds = true

        switch padding {
        case .left(let spacing):
            let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: spacing, height: frame.height))
            leftView = paddingView
            rightViewMode = .always

        case .right(let spacing):
            let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: spacing, height: frame.height))
            rightView = paddingView
            rightViewMode = .always

        case .both(let spacing):
            let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: spacing, height: frame.height))
            leftView = paddingView
            leftViewMode = .always
            rightView = paddingView
            rightViewMode = .always
        }
    }
}

extension UITableView {
    
    /// Creates a header similar in style to the grouped table view style headers
    func getHeaderLabel(
        title: String,
        color: UIColor,
        backgroundColor: UIColor,
        font: UIFont = .systemFont(ofSize: 24),
        inset: CGFloat = 20
    ) -> UIButton {
        let label = UIButton(frame: .zero)
        label.contentEdgeInsets = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: 0)
        label.isUserInteractionEnabled = false
        label.titleLabel?.font = font
        label.contentHorizontalAlignment = .left
        label.setTitle(title, for: .normal)
        label.setTitleColor(color, for: .normal)
        label.backgroundColor = backgroundColor
        label.sizeToFit()
        
        return label
    }
}

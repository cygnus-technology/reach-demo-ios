//
//  SetupRemoteSupportViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 3/8/21.
//  Copyright © 2021 Cygnus. All rights reserved.
//

import UIKit
import RemoteSupport
import PromiseKit

class SetupSupportViewController: UIViewController {
    @IBOutlet weak var pinTextField: UITextField!
    @IBOutlet weak var continueButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var remoteSupportImageView: UIImageView!
    @IBOutlet weak var hostButton: UIButton!
    
    var remoteSupport: RemoteSupportClient?
    var logger: TextViewLogger
    var connectedDevice: BluetoothDevice!
    var host = false
    
    private var loaded = false
    
    required init?(coder: NSCoder) {
        logger = TextViewLogger()
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        pinTextField.delegate = self
        hostButton.layer.borderColor = UIColor.systemBlue.cgColor

        continueButton.setBackgroundImage(continueButton.backgroundColor?.image(continueButton.bounds.size), for: .normal)
        continueButton.setTitleColor(.white, for: .normal)
        
        let disabledColor = UIColor(red: 0.45490196078, green: 0.45490196078, blue: 0.50196078431, alpha: 0.08)
        continueButton.setBackgroundImage(disabledColor.image(continueButton.bounds.size), for: .disabled)
        continueButton.setTitleColor(UIColor(red: 0.24, green: 0.24, blue: 0.26, alpha: 0.3), for: .disabled)
        continueButton.backgroundColor = nil
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardNotification(notification:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        navigationController?.setNavigationBarHidden(true, animated: true)
        pinTextField.text = ""
        continueButton.isEnabled = false
        pinTextField.returnKeyType = .default
        
        // FIXME: Add in your API key
        remoteSupport = RemoteSupportClient(apiUrlBase: "https://api.cygnusreach.com", apiKey: "", retainLogs: true, timeout: 5, logger: logger, delegate: self)
        
        if loaded {
            showToast(message: "Disconnected")
        }
        
        loaded = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        NotificationCenter.default.removeObserver(self)
        view.gestureRecognizers?.forEach { view.removeGestureRecognizer($0) }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touches.first?.view != continueButton {
            view.endEditing(true)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showRemoteSupport", let destinationVc = segue.destination as? SupportSessionViewController {
            destinationVc.connectedDevice = self.connectedDevice
            destinationVc.remoteSupport = self.remoteSupport
            destinationVc.logger = self.logger
        }
    }
    
    @IBAction func backButtonTapped(_ sender: Any) {
        navigationController?.popViewController(animated: true)
    }
    
    @IBAction func continueButtonTapped(_ sender: Any) {
        attemptSession()
    }
    
    @IBAction func hostButtonTapped(_ sender: Any) {
        self.host = true
        
        remoteSupport?.initiateSupportSession().done { pin in
            self.pinTextField.text = pin
        }.catch { error in
            self.showAlert(message: error.localizedDescription)
        }
    }
    
    @IBAction func devTaps(_ sender: Any) {
        hostButton.isHidden = false
    }
    
    func attemptSession() {
        let pin = pinTextField.text!
        self.continueButton.isHidden = true
        self.activityIndicator.startAnimating()
        
        remoteSupport?.connectToSupportSession(pin: pin).done {
            ProductService.shared.setRemoteSupportPin(pin)
            self.performSegue(withIdentifier: "showRemoteSupport", sender: self)
        }.catch { error in
            if let error = error as? RemoteSupportError {
                self.showAlert(title: error.title, message: error.localizedDescription, buttonTitle: "Dismiss")
            } else {
                self.showAlert(title: "Error", message: error.localizedDescription, buttonTitle: "Dismiss")
            }
        }.finally {
            self.continueButton.isHidden = false
            self.activityIndicator.stopAnimating()
        }
    }
}

extension SetupSupportViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        if textField.text!.count == 5 {
            attemptSession()
        }
        
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let newText = (textField.text! as NSString).replacingCharacters(in: range, with: string)
        let allowedCharacters = CharacterSet.decimalDigits
        if newText.rangeOfCharacter(from: allowedCharacters.inverted) != nil {
            return false
        }
        
        continueButton.isEnabled = newText.count == 5
        textField.returnKeyType = newText.count == 5 ? .go : .default
        textField.reloadInputViews()
        
        return true
    }
}

extension SetupSupportViewController: RemoteSupportDelegate {
    func remoteSupportDidConnect() {
        if host {
            self.performSegue(withIdentifier: "showRemoteSupport", sender: self)
        }
    }
}

// MARK: - Keyboard
extension SetupSupportViewController {
    @objc func keyboardNotification(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue
            let keyboardIsDown = keyboardFrame.origin.y >= UIScreen.main.bounds.size.height
            let bottomConstraintConstant = keyboardIsDown ? 17 : keyboardFrame.size.height + 17
            
            let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
            let animationCurveRawNSN = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber
            let animationCurveRaw = animationCurveRawNSN?.uintValue ?? UIView.AnimationOptions.curveEaseInOut.rawValue
            let animationCurve = UIView.AnimationOptions(rawValue: animationCurveRaw)

            UIView.animate(withDuration: duration, delay: 0, options: animationCurve, animations: {
                self.remoteSupportImageView.alpha = keyboardIsDown ? 1 : 0
                self.bottomConstraint.constant = bottomConstraintConstant
                self.view.layoutIfNeeded()
            }, completion: nil)
        }
    }
}

// MARK: - Toast
extension SetupSupportViewController {
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
        
        if #available(iOS 13.0, *) {
            cancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        } else {
            cancelButton.setImage(#imageLiteral(resourceName: "close"), for: .normal)
        }
        
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
}

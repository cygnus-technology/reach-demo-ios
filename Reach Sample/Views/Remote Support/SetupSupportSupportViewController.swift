//
//  SetupRemoteSupportViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 1/13/20.
//  Copyright © 2020 i3pd. All rights reserved.
//

import UIKit
import RemoteSupport
import PromiseKit
import Combine

class SetupSupportViewController: UIViewController {
    @IBOutlet weak var pinTextField: UITextField!
    @IBOutlet weak var continueButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var remoteSupportImageView: UIImageView!
    @IBOutlet weak var hostButton: UIButton!
    
    var connectedDevice: BluetoothDevice?
    var host = false
    
    private var loaded = false
    private var bag = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        pinTextField.delegate = self
        hostButton.layer.borderColor = UIColor.systemBlue.cgColor

        continueButton.setBackgroundImage(continueButton.backgroundColor?.image(continueButton.bounds.size), for: .normal)
        continueButton.setTitleColor(.white, for: .normal)
        
        let disabledColor = Colors.accent.color.withAlphaComponent(0.4)
        let disabledText = UIColor.white.withAlphaComponent(0.4)
        continueButton.setBackgroundImage(disabledColor.image(continueButton.bounds.size), for: .disabled)
        continueButton.setTitleColor(disabledText, for: .disabled)
        continueButton.backgroundColor = nil
        
        SupportService.shared.$remoteSupport
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rs in self?.setupSession() }
            .store(in: &bag)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if SupportService.shared.sessionActive {
            if !isMovingToParent {
                navigationController?.popViewController(animated: true)
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardNotification(notification:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        pinTextField.text = ""
        continueButton.isEnabled = false
        pinTextField.returnKeyType = .default
        
        if loaded && !SupportService.shared.sessionActive {
            showToast(message: "Disconnected")
        }
        
        loaded = true
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if SupportService.shared.sessionActive && isMovingToParent {
            performSegue(withIdentifier: "showRemoteSupport", sender: self)
        }
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
    
    @IBAction func continueButtonTapped(_ sender: Any) {
        attemptSession()
    }
    
    @IBAction func hostButtonTapped(_ sender: Any) {
        host = true
        setupSession()
        SupportService.shared.hostSession(apiKey: ProductService.shared.apiKey).done { pin in
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
        continueButton.isHidden = true
        activityIndicator.startAnimating()
        
        SupportService.shared.connectToSession(pin: pin, apiKey: ProductService.shared.apiKey).done {
            ProductService.shared.setRemoteSupportPin(pin)
        }.catch { error in
            self.continueButton.isHidden = false
            self.activityIndicator.stopAnimating()
            
            if let error = error as? RemoteSupportError {
                self.showAlert(title: error.title, message: error.localizedDescription, buttonTitle: "Dismiss")
            } else {
                self.showAlert(title: "Error", message: error.localizedDescription, buttonTitle: "Dismiss")
            }
        }
    }
    
    private func setupSession() {
        SupportService.shared.remoteSupport?.onConnect
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handleConnect() }
            .store(in: &bag)
    }
}

// MARK: - Remote Support
extension SetupSupportViewController {
    
    private func handleConnect() {
        performSegue(withIdentifier: "showRemoteSupport", sender: self)
        continueButton.isHidden = false
        activityIndicator.stopAnimating()
    }
}

// MARK: - Text Field Delegate
extension SetupSupportViewController: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        if textField.text!.count == 5 {
            attemptSession()
        }
        
        return true
    }
    
    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        textField.returnKeyType = .default
        textField.reloadInputViews()
        continueButton.isEnabled = false
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

// MARK: - Keyboard
extension SetupSupportViewController {
    
    @objc func keyboardNotification(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue
            let keyboardIsDown = keyboardFrame.origin.y >= UIScreen.main.bounds.size.height
            let bottomConstraintConstant = keyboardIsDown ? 40 : keyboardFrame.size.height + 17
            // Don't add constraint if running on a mac or another device without a visible keyboard
            if keyboardFrame.height == 0 { return }
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

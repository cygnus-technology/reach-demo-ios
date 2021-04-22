//
//  TextViewLogger.swift
//  Reach Sample
//
//  Created by Cygnus on 3/8/21.
//  Copyright © 2021 Cygnus. All rights reserved.
//

import UIKit
import RemoteSupport

class TextViewLogger: Logger {
    weak var textView: UITextView?
    private var logs = [String]()
    private var timer: Timer?
    
    init(textView: UITextView? = nil) {
        self.textView = textView
        self.textView?.layoutManager.allowsNonContiguousLayout = false
        self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let logs = self?.logs else { return }
            self?.textView?.text = logs.joined(separator: "\n")
            
            let index = self?.textView?.text.count ?? 0
            self?.textView?.scrollRangeToVisible(NSRange(location: index, length: 0))
        }
    }
    
    deinit {
        self.timer?.invalidate()
    }
    
    func clearText() {
        self.logs = []
        self.textView?.text = ""
    }
    
    func trace(_ msg: String, _ data: PrintableMap?...) {
        log(message: msg, level: "TRACE")
    }
    
    func debug(_ msg: String, _ data: PrintableMap?...) {
        log(message: msg, level: "DEBUG")
    }
    
    func error(_ msg: String, _ data: PrintableMap?...) {
        log(message: msg, level: "ERROR")
    }
    
    func info(_ msg: String, _ data: PrintableMap?...) {
        log(message: msg, level: "INFO")
    }
    
    func warn(_ msg: String, _ data: PrintableMap?...) {
        log(message: msg, level: "WARNING")
    }
    
    private func log(message: String, level: String) {
        print("\(level): \(message)")
        
        DispatchQueue.main.async {
            self.logs.append("\(level): " + message)
        }
    }
}

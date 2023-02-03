//
//  DashboardViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 6/13/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import UIKit

class DashboardViewController: UIViewController {
    
    @IBOutlet weak var greetingLabel: UILabel!
    @IBOutlet weak var sessionButton: PrimaryButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        greetingLabel.text = "Hello"
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: true)
        
        if SupportService.shared.sessionActive {
            sessionButton.setTitle("BACK TO SESSION", for: .normal)
        } else {
            sessionButton.setTitle("START A SUPPORT SESSION", for: .normal)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: true)
    }
}

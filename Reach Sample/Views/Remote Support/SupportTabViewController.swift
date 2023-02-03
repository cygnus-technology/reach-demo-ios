//
//  SupportPageViewController.swift
//  Reach Sample
//
//  Created by Cygnus on 5/31/22.
//  Copyright © 2022 i3pd. All rights reserved.
//

import UIKit
import RemoteSupport

protocol SupportTabViewController: UIViewController {}

extension SupportTabViewController {
    var remoteSupport: RemoteSupportClient? { SupportService.shared.remoteSupport }
}

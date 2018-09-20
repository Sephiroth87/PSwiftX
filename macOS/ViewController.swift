//
//  ViewController.swift
//  PSwiftX
//
//  Created by Fabio Ritrovato on 05/02/2017.
//  Copyright © 2017 orange in a day. All rights reserved.
//

import Cocoa
import PSX

class ViewController: NSViewController {

    let psx = PSX(biosData: try! Data(contentsOf: Bundle.main.url(forResource: "SCPH1001", withExtension: "BIN", subdirectory:"BIOS")!))

    override func viewDidLoad() {
        super.viewDidLoad()

        psx.run()
    }

}


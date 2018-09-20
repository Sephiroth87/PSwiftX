//
//  Addressable.swift
//  PSX
//
//  Created by Fabio on 20/04/2017.
//  Copyright © 2017 orange in a day. All rights reserved.
//

protocol Addressable {
    
    func read(at: UInt32) -> UInt8
    func read(at: UInt32) -> UInt16
    func read(at: UInt32) -> UInt32
    
    func write8(_ value: UInt32, at: UInt32)
    func write16(_ value: UInt32, at: UInt32)
    func write32(_ value: UInt32, at: UInt32)
    
}

//
//  Math.swift
//  PSX
//
//  Created by Fabio on 10/02/2017.
//  Copyright © 2017 orange in a day. All rights reserved.
//

func &+(left: UInt32, right: Int16) -> UInt32 {
    return UInt32(bitPattern: Int32(truncatingBitPattern: Int64(left) + Int64(right)))
}

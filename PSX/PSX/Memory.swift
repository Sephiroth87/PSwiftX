//
//  Memory.swift
//  PSX
//
//  Created by Fabio Ritrovato on 05/02/2017.
//  Copyright © 2017 orange in a day. All rights reserved.
//

import Foundation

private class MemoryRegion: Addressable {
    
    private var storage: [UInt8]
    init(initialValue: [UInt8]) {
        storage = initialValue
    }
    
    func read(at: UInt32) -> UInt8 { return storage[Int(at)] }
    func read(at: UInt32) -> UInt16 { return UInt16(storage[Int(at)]) | UInt16(storage[Int(at + 1)]) << 8 }
    func read(at: UInt32) -> UInt32 { return UInt32(storage[Int(at)]) | UInt32(storage[Int(at + 1)]) << 8 | UInt32(storage[Int(at + 2)]) << 16 | UInt32(storage[Int(at + 3)]) << 24 }
    
    func write8(_ value: UInt32, at: UInt32) { storage[Int(at)] = UInt8(truncatingBitPattern: value) }
    func write16(_ value: UInt32, at: UInt32) { storage[Int(at)] = UInt8(truncatingBitPattern: value); storage[Int(at + 1)] = UInt8(truncatingBitPattern: value >> 8) }
    func write32(_ value: UInt32, at: UInt32) { storage[Int(at)] = UInt8(truncatingBitPattern: value); storage[Int(at + 1)] = UInt8(truncatingBitPattern: value >> 8); storage[Int(at + 2)] = UInt8(truncatingBitPattern: value >> 16); storage[Int(at + 3)] = UInt8(truncatingBitPattern: value >> 24) }
}

private class ReadOnlyMemoryRegion: MemoryRegion {
    
    override func write8(_ value: UInt32, at: UInt32) {}
    override func write16(_ value: UInt32, at: UInt32) {}
    override func write32(_ value: UInt32, at: UInt32) {}
    
}

private typealias ConstantMemory = UInt8
extension ConstantMemory: Addressable {
    
    func read(at: UInt32) -> UInt8 { return self }
    func read(at: UInt32) -> UInt16 { return UInt16(self) }
    func read(at: UInt32) -> UInt32 { return UInt32(self) }
    
    func write8(_ value: UInt32, at: UInt32) {}
    func write16(_ value: UInt32, at: UInt32) {}
    func write32(_ value: UInt32, at: UInt32) {}
    
}

internal final class Memory: Addressable {

    private var ram = MemoryRegion(initialValue: [UInt8](repeating: 0x87, count: 2097152))
    private let bios: ReadOnlyMemoryRegion
    
    internal var dma: DMA!

    init(biosData: Data) {
        bios = ReadOnlyMemoryRegion(initialValue: [UInt8](biosData))
        //TODO: Randomize ram with garbage
    }
    
    static private let masks: [UInt32] = [0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0x7FFFFFFF, 0x1FFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF]
    
    private func physicalAddress(from: UInt32) -> UInt32 {
        return from & Memory.masks[Int(from >> 29)]
    }
    
    private func target(at: UInt32) -> (Addressable, UInt32)? {
        let address = physicalAddress(from: at)
        switch address {
        case 0x00000000...0x001FFFFF: return (ram, address)
        case 0x1F000000...0x1F07FFFF: return (ConstantMemory(0xFF), 0) //Expansion 1
        case 0x1F801000...0x1F801023: return (ConstantMemory(0), 0) //Memory control
        case 0x1F801060...0x1F801063: return (ConstantMemory(0), 0) //RAM size
        case 0x1F801070...0x1F801077: return (ConstantMemory(0), 0) //IRQ control
        case 0x1F801080...0x1F8010FF: return (dma, address - 0x1F801080)
        case 0x1F801100...0x1F80112F: return (ConstantMemory(0), 0) //Timers
        case 0x1F801810...0x1F801816: return (ConstantMemory(0), 0) //GPU
        case 0x1F801817: return (ConstantMemory(0x10), 0) //GPU
        case 0x1F801C00...0x1F801E80: return (ConstantMemory(0), 0) //SPU
        case 0x1F802000...0x1F80207F: return (ConstantMemory(0), 0) //Expansion 2
        case 0x1FC00000...0x1FC7FFFF: return (bios, address - 0x1FC00000)
        case 0xFFFE0130...0xFFFE0133: return (ConstantMemory(0), 0) //Cache control
        default: return nil
        }
    }

    func read(at: UInt32) -> UInt8 {
        guard let (target, address) = target(at: at) else { fatalError("Unknown read address \(String(format: "%08X", at))") }
        return target.read(at: address)
    }
    
    func read(at: UInt32) -> UInt16 {
        guard let (target, address) = target(at: at) else { fatalError("Unknown read address \(String(format: "%08X", at))") }
        return target.read(at: address)
    }
    
    func read(at: UInt32) -> UInt32 {
        guard let (target, address) = target(at: at) else { fatalError("Unknown read address \(String(format: "%08X", at))") }
        return target.read(at: address)
    }
    
    func write8(_ value: UInt32, at: UInt32) {
        guard let (target, address) = target(at: at) else { fatalError("Unknown write address \(String(format: "%08X", at))") }
        target.write8(value, at: address)
    }
    
    func write16(_ value: UInt32, at: UInt32) {
        guard let (target, address) = target(at: at) else { fatalError("Unknown write address \(String(format: "%08X", at))") }
        target.write16(value, at: address)
    }
    
    func write32(_ value: UInt32, at: UInt32) {
        guard let (target, address) = target(at: at) else { fatalError("Unknown write address \(String(format: "%08X", at))") }
        target.write32(value, at: address)
    }

}

//
//  DMA.swift
//  PSX
//
//  Created by Fabio on 20/04/2017.
//  Copyright © 2017 orange in a day. All rights reserved.
//

private struct DMAChannel {
    
    var madr: UInt32 = 0
    var bcr: UInt32 = 0
    var chcr: UInt32 = 0
    
}

private struct DMAState {
    
    var channels = [DMAChannel](repeating: DMAChannel(), count: 7)
    var control: UInt32 = 0x07654321
    var interrupt: UInt32 = 0x00000000
    
}

internal final class DMA: Addressable {
    
    private var state = DMAState()
    
    func read(at: UInt32) -> UInt8 { fatalError("DMA read8") }
    func read(at: UInt32) -> UInt16 { fatalError("DMA read16") }
    func read(at: UInt32) -> UInt32 {
        switch at {
        case 0x01...0x06F:
            let channel = Int(at & 0x70 >> 4)
            switch at & 0x0F {
            case 0x00: return state.channels[channel].madr
            case 0x04: return state.channels[channel].bcr
            case 0x08: return state.channels[channel].chcr
            default: fatalError("Unknown DMA read at \(String(format: "%08X", at))")
            }
        case 0x70: return state.control
        case 0x74: return state.interrupt
        default: fatalError("Unknown DMA read at \(String(format: "%08X", at))")
        }
    }
    
    func write8(_ value: UInt32, at: UInt32) { fatalError("DMA write8") }
    func write16(_ value: UInt32, at: UInt32) { fatalError("DMA write16") }
    func write32(_ value: UInt32, at: UInt32) {
        switch at {
        case 0x01...0x06F:
            let channel = Int(at & 0x70 >> 4)
            switch at & 0x0F {
            case 0x00: state.channels[channel].madr = value
            case 0x04: state.channels[channel].bcr = value
            case 0x08: state.channels[channel].chcr = value
            default: fatalError("Unknown DMA write at \(String(format: "%08X", at))")
            }
        case 0x70: state.control = value
        case 0x74: state.interrupt = value
        default: fatalError("Unknown DMA write at \(String(format: "%08X", at))")
        }
    }
    
}

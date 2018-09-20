//
//  R3000.swift
//  PSX
//
//  Created by Fabio Ritrovato on 05/02/2017.
//  Copyright © 2017 orange in a day. All rights reserved.
//

private typealias Instruction = UInt32
private extension Instruction {
    
    var opcode: UInt8 {
        return UInt8(truncatingBitPattern: self >> 26)
    }
    
    var secondaryOpcode: UInt8 {
        return UInt8(truncatingBitPattern: self & 0x0000003F)
    }

    var copOpcode: UInt8 {
        return UInt8(truncatingBitPattern: (self >> 21) & 0x1F)
    }

    var rs: Int {
        return Int((self >> 21) & 0x1F)
    }
    
    var rt: Int {
        return Int((self >> 16) & 0x1F)
    }
    
    var rd: Int {
        return Int((self >> 11) & 0x1F)
    }
    
    var imm: UInt16 {
        return UInt16(truncatingBitPattern: self)
    }
    
    var imm5: UInt8 {
        return UInt8((self >> 6) & 0x1F)
    }

    var imm26: UInt32 {
        return self & 0x03FFFFFF
    }

}

private typealias LoadDelay = (r: Int, value: UInt32)

private enum ExceptionCause: UInt32 {
    case loadAddress = 0x4
    case storeAddress = 0x5
    case syscall = 0x8
    case overflow = 0xC
}

private struct R3000State {
    
    var r = [UInt32](repeating: 0, count: 32)
    var hi: UInt32 = 0
    var lo: UInt32 = 0
    var pc: UInt32 = 0xBFC00000
    
    var cop0r = [UInt32](repeating: 0, count: 32)
    
    var currentPc: UInt32 = 0xBFC00000
    var nextPc: UInt32 = 0xBFC00004
    var loadDelaySlot = LoadDelay(r: 0, value: 0)
    var didBranch = false
    var isBranchDelaySlot = false
    
}

internal final class R3000 {

    private var state = R3000State()

    internal weak var memory: Memory!

    func step() {
        state.currentPc = state.pc
        if state.currentPc % 4 != 0 {
            exception(cause: .loadAddress)
            return
        }
        let i: Instruction = memory.read(at: state.pc)
        state.pc = state.nextPc
        state.nextPc = state.pc &+ 4
        state.isBranchDelaySlot = state.didBranch
        state.didBranch = false
        switch i.opcode {
        case 0b000000:
            switch i.secondaryOpcode {
            case 0b000000: sll(i)
            case 0b000010: srl(i)
            case 0b000011: sra(i)
            case 0b000100: sllv(i)
            case 0b000110: srlv(i)
            case 0b000111: srav(i)
            case 0b001000: jr(i)
            case 0b001001: jalr(i)
            case 0b001100: syscall(i)
            case 0b010000: mfhi(i)
            case 0b010001: mthi(i)
            case 0b010010: mflo(i)
            case 0b010011: mtlo(i)
            case 0b011001: multu(i)
            case 0b011010: div(i)
            case 0b011011: divu(i)
            case 0b100000: add(i)
            case 0b100001: addu(i)
            case 0b100011: subu(i)
            case 0b100100: and(i)
            case 0b100101: or(i)
            case 0b100110: xor(i)
            case 0b100111: nor(i)
            case 0b101010: slt(i)
            case 0b101011: sltu(i)
            default:
                fatalError("Unknown secondary opcode: \(String(i.secondaryOpcode, radix: 2)) (\(String(format: "%02X", i.secondaryOpcode))) - instruction: " + String(format: "%08X", i))
            }
        case 0b000001:
            switch i.rt {
            case 0b00000: bltz(i)
            case 0b00001: bgez(i)
            case 0b10000: bltzal(i)
            case 0b10001: bgezal(i)
            default: fatalError()
            }
        case 0b000010: j(i)
        case 0b000011: jal(i)
        case 0b000100: beq(i)
        case 0b000101: bne(i)
        case 0b000110: blez(i)
        case 0b000111: bgtz(i)
        case 0b001000: addi(i)
        case 0b001001: addiu(i)
        case 0b001010: slti(i)
        case 0b001011: sltiu(i)
        case 0b001100: andi(i)
        case 0b001101: ori(i)
        case 0b001111: lui(i)
        case 0b010000:
            switch i.copOpcode {
            case 0b00000: mfc0(i)
            case 0b00100: mtc0(i)
            case 0b10000: rfe(i)
            default:
                fatalError("Unknown cop opcode: \(String(i.copOpcode, radix: 2)) (\(String(format: "%02X", i.copOpcode))) - instruction: " + String(format: "%08X", i))
            }
        case 0b100000: lb(i)
        case 0b100001: lh(i)
        case 0b100011: lw(i)
        case 0b100100: lbu(i)
        case 0b100101: lhu(i)
        case 0b101000: sb(i)
        case 0b101001: sh(i)
        case 0b101011: sw(i)
        default:
            fatalError("Unknown opcode: \(String(i.opcode, radix: 2)) (\(String(format: "%02X", i.opcode))) - instruction: " + String(format: "%08X", i))
        }
        setRegister(state.loadDelaySlot.r, value: state.loadDelaySlot.value)
    }
    
    //MARK: Helpers
    
    private func setRegister(_ r: Int, value: UInt32) {
        state.r[r] = value
        state.r[0] = 0
        state.loadDelaySlot = LoadDelay(r: 0, value: 0)
    }

    private func branch(_ offset: Int16) {
        state.nextPc = state.pc &+ (offset << 2)
        state.didBranch = true
    }
    
    private func exception(cause: ExceptionCause) {
        var cause = cause.rawValue << 2
        var sr = state.cop0r[12]
        let handler: UInt32 = sr & (1 << 22) != 0 ? 0xBFC00180 : 0x80000080
        let mode = sr & 0x3F
        sr &= ~0x3F
        sr |= (mode << 2) & 0x3F
        state.cop0r[12] = sr
        state.pc = handler
        state.nextPc = state.pc &+ 4
        if state.isBranchDelaySlot {
            state.cop0r[14] = state.currentPc &- 4
            cause |= 1 << 31
        } else {
            state.cop0r[14] = state.currentPc
        }
        state.cop0r[13] = cause
    }
    
    //MARK: Opcodes
    
    private func add(_ i: Instruction) {
        if let v = UInt32(exactly: Int64(state.r[i.rs]) + Int64(state.r[i.rt])) {
            setRegister(i.rd, value: v)
        } else {
            exception(cause: .overflow)
        }
    }
    
    private func addi(_ i: Instruction) {
        if let v = UInt32(exactly: Int64(state.r[i.rs]) + Int64(Int16(bitPattern: i.imm))) {
            setRegister(i.rt, value: v)
        } else {
            exception(cause: .overflow)
        }
    }

    private func addiu(_ i: Instruction) {
        setRegister(i.rt, value: state.r[i.rs] &+ Int16(bitPattern: i.imm))
    }
    
    private func addu(_ i: Instruction) {
        setRegister(i.rd, value: state.r[i.rs] &+ state.r[i.rt])
    }
    
    private func and(_ i: Instruction) {
        setRegister(i.rd, value: state.r[i.rs] & state.r[i.rt])
    }
    
    private func andi(_ i: Instruction) {
        setRegister(i.rt, value: state.r[i.rs] & UInt32(i.imm))
    }
    
    private func beq(_ i: Instruction) {
        if state.r[i.rs] == state.r[i.rt] {
            branch(Int16(bitPattern: i.imm))
        }
    }
    
    private func bgez(_ i: Instruction) {
        if Int32(bitPattern: state.r[i.rs]) >= 0 {
            branch(Int16(bitPattern: i.imm))
        }
    }

    private func bgezal(_ i: Instruction) {
        if Int32(bitPattern: state.r[i.rs]) >= 0 {
            setRegister(31, value: state.nextPc)
            branch(Int16(bitPattern: i.imm))
        }
    }

    private func bgtz(_ i: Instruction) {
        if Int32(bitPattern: state.r[i.rs]) > 0 {
            branch(Int16(bitPattern: i.imm))
        }
    }
    
    private func blez(_ i: Instruction) {
        if Int32(bitPattern: state.r[i.rs]) <= 0 {
            branch(Int16(bitPattern: i.imm))
        }
    }
    
    private func bltz(_ i: Instruction) {
        if Int32(bitPattern: state.r[i.rs]) < 0 {
            branch(Int16(bitPattern: i.imm))
        }
    }
    
    private func bltzal(_ i: Instruction) {
        if Int32(bitPattern: state.r[i.rs]) < 0 {
            setRegister(31, value: state.nextPc)
            branch(Int16(bitPattern: i.imm))
        }
    }

    private func bne(_ i: Instruction) {
        if state.r[i.rs] != state.r[i.rt] {
            branch(Int16(bitPattern: i.imm))
        }
    }
    
    private func div(_ i: Instruction) {
        let n = Int32(bitPattern: state.r[i.rs])
        let d = Int32(bitPattern: state.r[i.rt])
        if d == 0 {
            state.hi = UInt32(bitPattern: n)
            state.lo = n >= 0 ? 0xFFFFFFFF : 1
        } else if n == Int32.min && d == -1 {
            state.hi = 0
            state.lo = 0x80000000
        } else {
            state.hi = UInt32(bitPattern: n % d)
            state.hi = UInt32(bitPattern: n / d)
        }
    }
    
    private func divu(_ i: Instruction) {
        let n = state.r[i.rs]
        let d = state.r[i.rt]
        if d == 0 {
            state.hi = n
            state.lo = 0xFFFFFFFF
        } else {
            state.hi = n % d
            state.hi = n / d
        }
    }

    private func j(_ i: Instruction) {
        state.nextPc = (state.pc & 0xF0000000) | (i.imm26 << 2)
        state.didBranch = true
    }
    
    private func jal(_ i: Instruction) {
        setRegister(31, value: state.nextPc)
        j(i)
    }
    
    private func jalr(_ i: Instruction) {
        setRegister(i.rd, value: state.nextPc)
        state.nextPc = state.r[i.rs]
        state.didBranch = true
    }
    
    private func jr(_ i: Instruction) {
        state.nextPc = state.r[i.rs]
        state.didBranch = true
    }
    
    private func lui(_ i: Instruction) {
        setRegister(i.rt, value: UInt32(i.imm) << 16)
    }
    
    private func lb(_ i: Instruction) {
        let v: UInt8 = memory.read(at: state.r[i.rs] &+ Int16(bitPattern: i.imm))
        state.loadDelaySlot = LoadDelay(r: i.rt, value: UInt32(bitPattern: Int32(Int8(bitPattern: v))))
    }
    
    private func lbu(_ i: Instruction) {
        let v: UInt8 = memory.read(at: state.r[i.rs] &+ Int16(bitPattern: i.imm))
        state.loadDelaySlot = LoadDelay(r: i.rt, value: UInt32(v))
    }
    
    private func lh(_ i: Instruction) {
        if case let address = state.r[i.rs] &+ Int16(bitPattern: i.imm), address % 2 == 0 {
            let v: UInt16 = memory.read(at: address)
            state.loadDelaySlot = LoadDelay(r: i.rt, value: UInt32(bitPattern: Int32(Int16(bitPattern: v))))
        } else {
            exception(cause: .loadAddress)
        }
    }

    private func lhu(_ i: Instruction) {
        if case let address = state.r[i.rs] &+ Int16(bitPattern: i.imm), address % 2 == 0 {
            let v: UInt16 = memory.read(at: address)
            state.loadDelaySlot = LoadDelay(r: i.rt, value: UInt32(v))
        } else {
            exception(cause: .loadAddress)
        }
    }
    
    private func lw(_ i: Instruction) {
        if case let address = state.r[i.rs] &+ Int16(bitPattern: i.imm), address % 4 == 0 {
            state.loadDelaySlot = LoadDelay(r: i.rt, value: memory.read(at: address))
        } else {
            exception(cause: .loadAddress)
        }
    }
    
    private func mfc0(_ i: Instruction) {
        switch i.rd {
        case 12, 13, 14:
            state.loadDelaySlot = LoadDelay(r: i.rt, value: state.cop0r[i.rd])
        default:
            fatalError("Unhandled read from cop0 register \(i.rd)")
        }
    }
    
    private func mfhi(_ i: Instruction) {
        setRegister(i.rd, value: state.hi)
    }
    
    private func mflo(_ i: Instruction) {
        setRegister(i.rd, value: state.lo)
    }

    private func mtc0(_ i: Instruction) {
        switch i.rd {
        case 3, 5, 6, 7, 9, 11, 13:
            if state.r[i.rt] != 0 {
                fatalError("Unhandled write to cop0 register \(i.rd)")
            }
        case 12:
            state.cop0r[i.rd] = state.r[i.rt]
        default:
            fatalError("Unhandled write to cop0 register \(i.rd)")
        }
    }
    
    private func mtlo(_ i: Instruction) {
        state.lo = state.r[i.rs]
    }
    
    private func mthi(_ i: Instruction) {
        state.hi = state.r[i.rs]
    }
    
    private func multu(_ i: Instruction) {
        let v = UInt64(state.r[i.rs]) * UInt64(state.r[i.rt])
        state.hi = UInt32(truncatingBitPattern: v >> 32)
        state.lo = UInt32(truncatingBitPattern: v)
    }
    
    private func nor(_ i: Instruction) {
        setRegister(i.rd, value: ~(state.r[i.rs] | state.r[i.rt]))
    }

    private func or(_ i: Instruction) {
        setRegister(i.rd, value: state.r[i.rs] | state.r[i.rt])
    }

    private func ori(_ i: Instruction) {
        setRegister(i.rt, value: state.r[i.rs] | UInt32(i.imm))
    }
    
    private func rfe(_ i: Instruction) {
        guard i & 0x3F == 0b010000 else { fatalError("Unknown cop opcode: \(String(i.copOpcode, radix: 2)) (\(String(format: "%02X", i.copOpcode))) - instruction: " + String(format: "%08X", i)) }
        var sr = state.cop0r[12]
        let mode = sr & 0x3F
        sr &= ~0x3F
        sr |= (mode >> 2)
        state.cop0r[12] = sr
    }
    
    private func sll(_ i: Instruction) {
        setRegister(i.rd, value: state.r[i.rt] << UInt32(i.imm5))
    }
    
    private func sllv(_ i: Instruction) {
        setRegister(i.rd, value: state.r[i.rt] << (state.r[i.rs] & 0x1F))
    }
    
    private func slt(_ i: Instruction) {
        Int32(bitPattern: state.r[i.rs]) < Int32(bitPattern: state.r[i.rt]) ? setRegister(i.rd, value: 1) : setRegister(i.rd, value: 0)
    }
    
    private func slti(_ i: Instruction) {
        Int32(bitPattern: state.r[i.rs]) < Int32(Int16(bitPattern: i.imm)) ? setRegister(i.rt, value: 1) : setRegister(i.rt, value: 0)
    }
    
    private func sltiu(_ i: Instruction) {
        state.r[i.rs] < UInt32(bitPattern: Int32(Int16(bitPattern: i.imm))) ? setRegister(i.rt, value: 1) : setRegister(i.rt, value: 0)
    }
    
    private func sltu(_ i: Instruction) {
        state.r[i.rs] < state.r[i.rt] ? setRegister(i.rd, value: 1) : setRegister(i.rd, value: 0)
    }
    
    private func sb(_ i: Instruction) {
        if state.cop0r[12] & 0x10000 != 0{
            // Cache is isolated , ignore write
            print("ignoring store while cache is isolated")
            return
        }
        memory.write8(state.r[i.rt], at: state.r[i.rs] &+ Int16(bitPattern: i.imm))
    }
    
    private func sh(_ i: Instruction) {
        if state.cop0r[12] & 0x10000 != 0{
            // Cache is isolated , ignore write
            print("ignoring store while cache is isolated")
            return
        }
        if case let address = state.r[i.rs] &+ Int16(bitPattern: i.imm), address % 2 == 0 {
            memory.write16(state.r[i.rt], at: address)
        } else {
            exception(cause: .storeAddress)
        }
    }
    
    private func sra(_ i: Instruction) {
        setRegister(i.rd, value: UInt32(bitPattern: Int32(bitPattern: state.r[i.rt]) >> Int32(i.imm5)))
    }
    
    private func srav(_ i: Instruction) {
        setRegister(i.rd, value: UInt32(bitPattern: Int32(bitPattern: state.r[i.rt]) >> Int32(state.r[i.rs] & 0x1F)))
    }
    
    private func srl(_ i: Instruction) {
        setRegister(i.rd, value: state.r[i.rt] >> UInt32(i.imm5))
    }
    
    private func srlv(_ i: Instruction) {
        setRegister(i.rd, value: state.r[i.rt] >> (state.r[i.rs] & 0x1F))
    }
    
    private func subu(_ i: Instruction) {
        setRegister(i.rd, value: state.r[i.rs] &- state.r[i.rt])
    }
    
    private func syscall(_ i: Instruction) {
        exception(cause: .syscall)
    }
    
    private func sw(_ i: Instruction) {
        if state.cop0r[12] & 0x10000 != 0{
            // Cache is isolated , ignore write 
            print("ignoring store while cache is isolated")
            return
        }
        if case let address = state.r[i.rs] &+ Int16(bitPattern: i.imm), address % 4 == 0 {
            memory.write32(state.r[i.rt], at: address)
        } else {
            exception(cause: .storeAddress)
        }
    }
    
    private func xor(_ i: Instruction) {
        setRegister(i.rd, value: state.r[i.rs] ^ state.r[i.rt])
    }

}

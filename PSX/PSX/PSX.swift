//
//  PSX.swift
//  PSX
//
//  Created by Fabio Ritrovato on 05/02/2017.
//  Copyright © 2017 orange in a day. All rights reserved.
//

import Foundation

public final class PSX {

    internal let cpu = R3000()
    internal let memory: Memory
    internal let dma = DMA()

    private let dispatchQueue = DispatchQueue(label: "main.loop", attributes: [])
    public internal(set) var running: Bool = false

    public init(biosData: Data) {
        memory = Memory(biosData: biosData)

        cpu.memory = memory
        memory.dma = dma
    }

    public func run() {
        if !running {
            running = true
            dispatchQueue.async(execute: mainLoop)
        }
    }

    @objc private func mainLoop() {
        while running {
            cpu.step()
        }
    }

}

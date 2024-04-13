package main

import "core:fmt"
import "core:intrinsics"

D: [8]u32
A: [8]u32
pc: u32
sr: u16
usp: u32
ssp: u32
user: bool
//vbr?

cpu_init :: proc()
{
    pc = 0x400000
    user = false
}

cpu_step :: proc() -> u64
{

    fmt.println("Decode")
    opcode := bus_read16(pc)
    pc += 2
    cpu_decode(opcode)

    return 2
}

cpu_decode :: proc(opcode: u16)
{
    code := (opcode >> 8)
    switch code {
        case:
            fmt.printf("Unhandled opcode: 0x%X\n", opcode)
            //panic("")
    }
}

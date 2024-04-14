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
        case 0x06:
            fmt.println("AddI?")
        case 0xD0..=0xDF:
            fmt.println("Add?")
            op1: i32
            op2: u32
            reg := (opcode >> 9) & 7
            opmode := (opcode >> 6) & 7
            mode := (opcode >> 3) & 7
            reg2 := (opcode >> 0) & 7

            switch (opmode) {
                case 0:
                    fmt.println("Opmode: 0")
                    op1 = i32(i8(D[reg2]))
                    op2 = D[reg]
                    fmt.printf("ea: D%d = %d\n", reg2, op1)
                    fmt.printf("Dn: D%d = %d\n", reg, op2)
                case :
                    fmt.printf("Unhandled opmode: %d\n", opmode)

            }
            switch mode {
                case 0:
                    fmt.println("Mode: 0")
                    res := u32(i32(op2) + op1)
                    fmt.printf("%d + %d = %d\n", op2, op1, res)
                    D[reg] = u32(res)
                case :
                    fmt.printf("Unhandled mode: %d\n", opmode)
            }
            
        case:
            fmt.printf("Unhandled opcode: 0x%X\n", opcode)
            //panic("")
    }
}

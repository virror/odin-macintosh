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

cpu_get_ea_data8 :: proc(mode: u16, reg: u16) -> (u8, u32)
{
    switch mode {
        case 0:
            return u8(D[reg]), 0
        case 2:
            return bus_read8(A[reg]), A[reg]
        case 3:
            addr := A[reg]
            if reg == 7 {
                A[reg] += 2
            } else {
                A[reg] += 1
            }
            return bus_read8(addr), addr
        case 4:
            if reg == 7 {
                A[reg] -= 2
            } else {
                A[reg] -= 1
            }
            return bus_read8(A[reg]), A[reg]
        case 5:
            ext1 := i16(bus_read16(pc))
            pc += 2
            addr:= u32(i64(A[reg]) + i64(ext1))
            return bus_read8(addr), addr
        case 6:
            ext1 := bus_read16(pc)
            da:= ext1 >> 15
            wl:= (ext1 >> 11) & 1
            reg:= (ext1 >> 12) & 7
            pc += 2
            index_reg: u32
            if da == 1 {
                index_reg = A[reg]
            } else {
                index_reg = D[reg]
            }
            if wl == 0 {
                index_reg = u32(u16(index_reg))
            }
            addr:= u32(i64(A[reg]) + i64(i8(ext1)) + i64(index_reg))
            return bus_read8(addr), addr
        case 7:
            switch reg {
                case 0:
                    ext1 := u32(bus_read16(pc))
                    pc += 2
                    return bus_read8(ext1), ext1
                case 1:
                    ext1 := bus_read16(pc)
                    pc += 2
                    ext2 := bus_read16(pc)
                    pc += 2
                    addr:= (u32(ext1) << 16) | u32(ext2)
                    return bus_read8(addr), addr
                case 2:
                    ext1 := i16(bus_read16(pc))
                    addr:= u32(i64(pc) + i64(ext1))
                    pc += 2
                    return bus_read8(addr), addr
                case 3:
                    ext1 := bus_read16(pc)
                    da:= ext1 >> 15
                    wl:= (ext1 >> 11) & 1
                    reg:= (ext1 >> 12) & 7
                    pc += 2
                    index_reg: i32
                    if da == 1 {
                        index_reg = i32(A[reg])
                    } else {
                        index_reg = i32(D[reg])
                    }
                    if wl == 0 {
                        index_reg = i32(i16(index_reg))
                    }
                    addr:= u32(i64(ext1) + i64(pc) + i64(index_reg))
                    return bus_read8(addr), addr
                case 4:
                    ext1 := u8(bus_read16(pc))
                    pc += 2
                    return u8(ext1), 0
                case:
                    fmt.printf("Unhandled 111 sub mode: %d\n", reg)
            }
        case:
            fmt.printf("Unhandled mode: %d\n", mode)
    }
    return 0, 0
}

cpu_decode :: proc(opcode: u16)
{
    code := (opcode >> 8)
    switch code {
        case 0x06:          //ADDI
            cpu_addi(opcode)
        case 0x50..=0x5F:
            if (opcode >> 6) & 3 == 3 {
                fmt.printf("Unhandled opcode: 0x%X\n", opcode)
            } else {
                cpu_addq(opcode)
            }
        case 0xD0..=0xDF:   //ADD
            cpu_add(opcode)
        case:
            fmt.printf("Unhandled opcode: 0x%X\n", opcode)
            //panic("")
    }
}

cpu_addi :: proc(opcode: u16)
{
    size := (opcode >> 6) & 3
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    imm: u32

    switch size {
        case 0:
            imm = u32(u8(bus_read16(pc)))
            pc += 2
        case 1:
            imm = u32(u16(bus_read16(pc)))
            pc += 2
        case 2:
            fmt.println("Unhandled size: 2")
    }
    ea_data, addr := cpu_get_ea_data8(mode, reg)
    data := ea_data + u8(imm)
    bus_write8(addr, u8(data))
}

cpu_addq :: proc(opcode: u16)
{
    data := (opcode >> 9) & 7
    if data == 0 {
        data = 8
    }
    size := (opcode >> 6) & 3
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case 0:
            ea_data, addr := cpu_get_ea_data8(mode, reg)
            bus_write8(addr, u8(data) + ea_data)
        case 1:
            fmt.println("Unhandled size: 1")
        case 2:
            fmt.println("Unhandled size: 2")
    }
}

cpu_add :: proc(opcode: u16)
{
    reg := (opcode >> 9) & 7
    dir := (opcode >> 8) & 1
    size := (opcode >> 6) & 3
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7
    dest_reg: u16

    switch size {
        case 0:
            ea_data, addr := cpu_get_ea_data8(mode, reg2)
            if dir == 1 {
                bus_write8(addr, u8(ea_data) + u8(D[reg]))
            } else {
                D[reg] = u32(i64(i8(ea_data)) + i64(D[reg]))
            }
        case 1:
            fmt.println("Unhandled size: 1")
        case 2:
            fmt.println("Unhandled size: 2")
    }
}

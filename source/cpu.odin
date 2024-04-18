package main

import "core:fmt"
import "core:intrinsics"

SR :: bit_field u16 {
    c: bool         | 1,
    v: bool         | 1,
    z: bool         | 1,
    n: bool         | 1,
    e: bool         | 1,
    na2: u8         | 3,
    intr_mask: u8   | 3,
    na1: bool       | 1,
    intr_enbl: bool | 1,
    super: bool     | 1,
    trace: u8       | 2,
}

D: [8]u32
A: [7]u32
pc: u32
sr: SR
usp: u32
ssp: u32
prefetch: [3]u16
//vbr?

cpu_init :: proc()
{
    pc = 0x400000
    sr.super = true
    prefetch[0] = bus_read16(pc)
    prefetch[2] = bus_read16(pc + 2)
}

cpu_prefetch :: proc()
{
    pc += 2
    prefetch[1] = prefetch[2]
    prefetch[2] = bus_read16(pc + 2)
    prefetch[0] = prefetch[1]
}

cpu_fetch :: proc() -> u16
{
    ret := prefetch[2]
    pc += 2
    prefetch[2] = bus_read16(pc + 2)
    return ret
}

cpu_step :: proc() -> u32
{
    fmt.println("Decode")
    cycles := cpu_decode(prefetch[0])
    return cycles
}

cpu_Areg_set :: proc(reg: u16, value: u32)
{
    if reg == 7 {
        if sr.super {
            ssp = value
        } else {
            usp = value
        }
    } else {
        A[reg] = value
    }
}

cpu_Areg_get :: proc(reg: u16) -> u32
{
    if reg == 7 {
        if sr.super {
            return ssp
        } else {
            return usp
        }
    } else {
        return A[reg]
    }
}

cpu_get_ea_data8 :: proc(mode: u16, reg: u16) -> (u8, u32)
{
    switch mode {
        case 0:
            return u8(D[reg]), 0
        case 2:
            data := cpu_Areg_get(reg)
            return bus_read8(data), data
        case 3:
            addr := cpu_Areg_get(reg)
            tmp_reg := addr
            if reg == 7 {
                tmp_reg += 2
            } else {
                tmp_reg += 1
            }
            cpu_Areg_set(reg, tmp_reg)
            return bus_read8(addr), addr
        case 4:
            data := cpu_Areg_get(reg)
            if reg == 7 {
                data -= 2
            } else {
                data -= 1
            }
            cpu_Areg_set(reg, data)
            return bus_read8(data), data
        case 5:
            ext1 := i16(cpu_fetch())
            addr:= u32(i64(cpu_Areg_get(reg)) + i64(ext1))
            return bus_read8(addr), addr
        case 6:
            ext1 := cpu_fetch()
            da:= ext1 >> 15
            wl:= (ext1 >> 11) & 1
            ireg:= (ext1 >> 12) & 7
            index_reg: u64
            if da == 1 {
                index_reg = u64(cpu_Areg_get(ireg))
            } else {
                index_reg = u64(D[ireg])
            }
            if wl == 0 {
                index_reg = u64(i32(i16(index_reg)))
            }
            addr:= u32(i64(cpu_Areg_get(reg)) + i64(i8(ext1)) + i64(index_reg))
            return bus_read8(addr), addr
        case 7:
            switch reg {
                case 0:
                    ext1 := u32(cpu_fetch())
                    addr := u32(i32(i16(ext1)))
                    return bus_read8(addr), addr
                case 1:
                    ext1 := cpu_fetch()
                    ext2 := cpu_fetch()
                    addr:= (u32(ext1) << 16) | u32(ext2)
                    return bus_read8(addr), addr
                case 2:
                    ext1 := i16(cpu_fetch())
                    addr:= u32(i64(pc) + i64(ext1))
                    return bus_read8(addr), addr
                case 3:
                    ext1 := cpu_fetch()
                    da:= ext1 >> 15
                    wl:= (ext1 >> 11) & 1
                    ireg:= (ext1 >> 12) & 7
                    index_reg: i32
                    if da == 1 {
                        index_reg = i32(cpu_Areg_get(ireg))
                    } else {
                        index_reg = i32(D[ireg])
                    }
                    if wl == 0 {
                        index_reg = i32(i16(index_reg))
                    }
                    addr:= u32(i64(ext1) + i64(pc) + i64(index_reg))
                    return bus_read8(addr), addr
                case 4:
                    ext1 := u8(cpu_fetch())
                    return u8(ext1), 0
                case:
                    fmt.printf("Unhandled 111 sub mode: %d\n", reg)
            }
        case:
            fmt.printf("Unhandled mode: %d\n", mode)
    }
    return 0, 0
}

cpu_get_addr_cycles_bw :: proc(mode: u16, reg: u16) -> u32
{
    switch mode {
        case 0, 1:
            return 0
        case 2, 3:
            return 4
        case 4:
            return 6
        case 5:
            return 8
        case 6:
            return 10
        case 7:
            switch reg {
                case 0, 2:
                    return 8
                case 1:
                    return 12
                case 3:
                    return 10
                case 4:
                    return 4
            }
    }
    return 0
}

cpu_decode :: proc(opcode: u16) -> u32
{
    code := (opcode >> 8)
    switch code {
        case 0x06:          //ADDI
            return cpu_addi(opcode)
        case 0x50..=0x5F:
            if (opcode >> 6) & 3 == 3 {
                fmt.printf("Unhandled opcode: 0x%X\n", opcode)
            } else {
                return cpu_addq(opcode)
            }
        case 0xD0..=0xDF:   //ADD
            return cpu_add(opcode)
        case:
            fmt.printf("Unhandled opcode: 0x%X\n", opcode)
            //panic("")
    }
    return 0
}

cpu_addi :: proc(opcode: u16) -> u32
{
    size := (opcode >> 6) & 3
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    imm: u32
    length := cpu_get_addr_cycles_bw(mode, reg)
    switch size {
        case 0:
            imm = u32(u8(cpu_fetch()))
        case 1:
            imm = u32(u16(cpu_fetch()))
        case 2:
            fmt.println("Unhandled size: 2")
    }
    if mode == 0 {
        length += 8
    } else {
        length += 12
    }
    ea_data, addr := cpu_get_ea_data8(mode, reg)
    data := ea_data + u8(imm)
    cpu_prefetch()
    bus_write8(addr, u8(data))
    return length
}

cpu_addq :: proc(opcode: u16) -> u32
{
    data := (opcode >> 9) & 7
    if data == 0 {
        data = 8
    }
    size := (opcode >> 6) & 3
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    length := cpu_get_addr_cycles_bw(mode, reg)

    switch size {
        case 0:
            if mode == 0 {
                D[reg] += u32(data)
                cpu_prefetch()
                length += 4
            } else {
                ea_data, addr := cpu_get_ea_data8(mode, reg)
                cpu_prefetch()
                bus_write8(addr, u8(data) + (ea_data))
                length += 8
            }
        case 1:
            fmt.println("Unhandled size: 1")
        case 2:
            fmt.println("Unhandled size: 2")
    }
    return length
}

cpu_add :: proc(opcode: u16) -> u32
{
    reg := (opcode >> 9) & 7
    dir := (opcode >> 8) & 1
    size := (opcode >> 6) & 3
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7
    dest_reg: u16
    length := cpu_get_addr_cycles_bw(mode, reg2)

    switch size {
        case 0:
            ea_data, addr := cpu_get_ea_data8(mode, reg2)
            cpu_prefetch()
            if dir == 1 {
                bus_write8(addr, u8(ea_data) + u8(D[reg]))
                length += 8
            } else {
                D[reg] = u32(i64(i8(ea_data)) + i64(D[reg]))
                length += 4
            }
        case 1:
            fmt.println("Unhandled size: 1")
        case 2:
            fmt.println("Unhandled size: 2")
    }
    return length
}

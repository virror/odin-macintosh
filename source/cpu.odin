package main

import "core:fmt"
import "base:intrinsics"

Exception :: enum {
    Reset,
    Interrupt,
    Uninitialized,
    Spurious,
    Trap,
    Illegal,
    Privilege,
    Trace,
    Bus,
    Address,
    Zero,
    CHK,
}

SR :: bit_field u16 {
    c: bool         | 1,
    v: bool         | 1,
    z: bool         | 1,
    n: bool         | 1,
    x: bool         | 1,
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
@(private="file")
cycles: u32

cpu_init :: proc()
{
    //pc = 0x400000
    cpu_exception(.Reset, 0, 0)
    cpu_refetch()
}

@(private="file")
cpu_refetch :: proc()
{
    prefetch[2] = bus_read16(pc)
    prefetch[1] = prefetch[2]
    prefetch[2] = bus_read16(pc + 2)
    prefetch[0] = prefetch[1]
}

@(private="file")
cpu_prefetch :: proc()
{
    pc += 2
    prefetch[1] = prefetch[2]
    prefetch[2] = bus_read16(pc + 2)
    prefetch[0] = prefetch[1]
}

@(private="file")
cpu_fetch :: proc() -> u16
{
    ret := prefetch[2]
    pc += 2
    prefetch[2] = bus_read16(pc + 2)
    cycles += 4
    return ret
}

cpu_step :: proc() -> u32
{
    fmt.println("Decode")
    cycles := cpu_decode(prefetch[0])
    return cycles
}

@(private="file")
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

@(private="file")
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

@(private="file")
cpu_get_address :: proc(mode: u16, reg: u16, size: u16) -> u32
{
    addr: u32
    switch mode {
        case 2:
            addr = cpu_Areg_get(reg)
        case 3:
            addr = cpu_Areg_get(reg)
            tmp_addr := addr
            switch size {
                case 0:
                    if reg == 7 {
                        tmp_addr += 2
                    } else {
                        tmp_addr += 1
                    }
                case 1:
                    tmp_addr += 2
                case 2:
                    tmp_addr += 4
            }
            cpu_Areg_set(reg, tmp_addr)
        case 4:
            addr = cpu_Areg_get(reg)
            switch size {
                case 0:
                    if reg == 7 {
                        addr -= 2
                    } else {
                        addr -= 1
                    }
                case 1:
                    addr -= 2
                case 2:
                    addr -= 4
            }
            cpu_Areg_set(reg, addr)
            cycles += 2
        case 5:
            ext1 := i16(cpu_fetch())
            addr = u32(i64(cpu_Areg_get(reg)) + i64(ext1))
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
            cycles += 2
            addr = u32(i64(cpu_Areg_get(reg)) + i64(i8(ext1)) + i64(index_reg))
        case 7:
            switch reg {
                case 0:
                    ext1 := u32(cpu_fetch())
                    addr = u32(i32(i16(ext1)))
                case 1:
                    ext1 := cpu_fetch()
                    ext2 := cpu_fetch()
                    addr = (u32(ext1) << 16) | u32(ext2)
                case 2:
                    ext1 := i16(cpu_fetch())
                    addr = u32(i64(pc) + i64(ext1))
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
                    cycles += 2
                    addr = u32(i64(ext1) + i64(pc) + i64(index_reg))
            }
    }

    return addr
}

@(private="file")
cpu_get_ea_data8 :: proc(mode: u16, reg: u16, addr: u32) -> u8
{
    data: u8
    if mode == 0 {
        data = u8(D[reg])
    } else if mode == 7 && reg == 4 {
        data = u8(cpu_fetch())
    } else {
        data = bus_read8(addr)
        cycles += 4
    }
    return data
}

@(private="file")
cpu_get_ea_data16 :: proc(mode: u16, reg: u16, addr: u32) -> u16
{
    data: u16
    if mode == 0 {
        data = u16(D[reg])
    } else if mode == 7 && reg == 4 {
        data = u16(cpu_fetch())
    } else {
        data = bus_read16(addr)
        cycles += 4
    }
    return data
}

@(private="file")
cpu_get_ea_data32 :: proc(mode: u16, reg: u16, addr: u32) -> u32
{
    data: u32
    if mode == 0 {
        data = D[reg]
    } else if mode == 7 && reg == 4 {
        data = u32(cpu_fetch())
    } else {
        data = bus_read32(addr)
        cycles += 8
    }
    return data
}

@(private="file")
cpu_get_exc_group :: proc(exc: Exception) -> u8
{
    switch exc {
        case .Reset, .Address, .Bus:
            return 0
        case .Trace, .Interrupt, .Illegal, .Privilege, .Spurious, .Uninitialized:
            return 1
        case .Trap, .CHK, .Zero:
            return 2
    }
    return 2
}

// TODO: Still needs loads of work
@(private="file")
cpu_exception :: proc(exc: Exception, addr: u32, opcode: u16)
{
    exc_vec: u32
    function_code :u16= 5
    r_w := true
    i_n := false
    tmp_sr := u16(sr)
    sr.super = true
    sr.trace = 0
    sr.intr_mask = 7    //TODO; Check this

    if exc == .Reset {
        ssp = bus_read32(0x00)
        pc = bus_read32(0x04)
        cpu_refetch()
        return
    }

    ssp -= 4
    bus_write32(ssp, pc)
    ssp -= 2
    bus_write16(ssp, tmp_sr)
    #partial switch exc {
        case .Bus:
            exc_vec = 8
            cycles += 50
        case .Address:
            exc_vec = 12
            cycles += 50
        case .Illegal:
            exc_vec = 16
            cycles += 34
        case .Zero:
            exc_vec = 20
            cycles += 38
        case .CHK:
            exc_vec = 24
            cycles += 40
        case .Trap:
            exc_vec = 28
            cycles += 34
        case .Privilege:
            exc_vec = 32
            cycles += 34
        case .Trace:
            exc_vec = 36
            cycles += 34
        case .Uninitialized:
            exc_vec = 60
            cycles += 44 //?
        case .Spurious:
            exc_vec = 96
            cycles += 44 //?
    }
    group := cpu_get_exc_group(exc)
    if group == 0 {
        ssp -= 2
        bus_write16(ssp, opcode)
        ssp -= 4
        bus_write32(ssp, addr)
        ssp -= 2
        apa:u16= ((opcode & 0xFFE0))
        apa |= u16(r_w) << 4
        apa |= u16(i_n) << 3
        apa |= function_code
        bus_write16(ssp, apa)
    }
    pc = bus_read32(exc_vec)
    cpu_refetch()
}

cpu_decode :: proc(opcode: u16) -> u32
{
    cycles = 0
    code := (opcode >> 8)
    switch code {
        case 0x06:          //ADDI
            cpu_addi(opcode)
        case 0x42:          //CLR
            cpu_clr(opcode)
        case 0x4E:
            sub_code := opcode & 0xFF
            switch sub_code {
                case 0x70:      //RESET
                    cpu_reset(opcode)
                case 0x71:      //NOP
                    cpu_nop(opcode)
                case:
                    fmt.printf("Unhandled opcode: 0x%X\n", opcode)
            }
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
    return cycles
}

@(private="file")
cpu_addi :: proc(opcode: u16)
{
    size := (opcode >> 6) & 3
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    imm: u32

    switch size {
        case 0:
            imm = u32(u8(cpu_fetch()))
        case 1:
            imm = u32(u16(cpu_fetch()))
        case 2:
            fmt.println("Unhandled size: 2")
    }
    if mode == 0 {
        cycles += 4
        cpu_prefetch()
        D[reg] += u32(u8(imm))
    } else {
        cycles += 8
        addr := cpu_get_address(mode, reg, size)
        ea_data := cpu_get_ea_data8(mode, reg, addr)
        data := ea_data + u8(imm)
        cpu_prefetch()
        bus_write8(addr, u8(data))
    }
}

@(private="file")
cpu_clr :: proc(opcode: u16)
{
    size := (opcode >> 6) & 3
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case 0:
            if mode == 0 {
                D[reg] = D[reg] & 0xFFFFFF00
                cycles += 4
            } else {
                addr := cpu_get_address(mode, reg, size)
                cycles += 4
                bus_write8(addr, 0)
                cycles += 8
            }
        case 1:
            if mode == 0 {
                D[reg] = D[reg] & 0xFFFF0000
                cycles += 4
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception(.Address, addr, opcode)
                    return
                }
                cycles += 4
                bus_write16(addr, 0)
                cycles += 8
            }
        case 2:
            if mode == 0 {
                D[reg] = 0
                cycles += 6
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception(.Address, addr, opcode)
                    return
                }
                cycles += 8
                bus_write32(addr, 0)
                cycles += 12
            }
    }
    sr.n = false
    sr.z = true
    sr.v = false
    sr.c = false
    cpu_prefetch()
}

@(private="file")
cpu_trap :: proc(opcode: u16)
{
}

@(private="file")
cpu_reset :: proc(opcode: u16)
{
    //TODO: Reset all external devices?
    if sr.super {
        cycles += 132
    } else {
        cpu_trap(opcode)
    }
    cpu_prefetch()
}

@(private="file")
cpu_nop :: proc(opcode: u16)
{
    cycles += 4
    cpu_prefetch()
}

@(private="file")
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
            if mode == 0 {
                D[reg] += u32(data)
                cpu_prefetch()
                cycles += 4
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                cpu_prefetch()
                bus_write8(addr, u8(data) + (ea_data))
                cycles += 8
            }
        case 1:
            fmt.println("Unhandled size: 1")
        case 2:
            fmt.println("Unhandled size: 2")
    }
}

@(private="file")
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
            addr := cpu_get_address(mode, reg2, size)
            ea_data := cpu_get_ea_data8(mode, reg2, addr)
            cpu_prefetch()
            if dir == 1 {
                if mode == 0 {
                    D[reg] += u32(ea_data)
                } else {
                    bus_write8(addr, u8(ea_data) + u8(D[reg]))
                }
                cycles += 8
            } else {
                D[reg] = u32(i64(i8(ea_data)) + i64(D[reg]))
                cycles += 4
            }
        case 1:
            fmt.println("Unhandled size: 1")
        case 2:
            fmt.println("Unhandled size: 2")
    }
}

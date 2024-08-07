package main

import "core:fmt"
import "core:math"
import "base:intrinsics"

/*TODO:
-Finish instructions and pass tests
--MOVE.w, l (23), (26)
-Check use of SSP
--Push/pop?
-Correct bus transaction order
-Exception timing?
*/
@(private="file")
Exception :: enum {
    Reset,
    Interrupt,
    Uninitialized,
    Spurious,
    Trap,
    TrapV,
    Illegal,
    Privilege,
    Trace,
    Bus,
    Address,
    Zero,
    CHK,
    Line1010,
    Line1111,
}

@(private="file")
Size :: enum {
    Byte,
    Word,
    Long,
}

@(private="file")
Operation :: enum {
    Add,
    Sub,
    And,
    Or,
}

@(private="file")
BitOp :: enum {
    Test,
    Set,
    Clear,
    Change,
}

@(private="file")
Conditional :: enum {
    T,
    F,
    HI,
    LS,
    CC,
    CS,
    NE,
    EQ,
    VC,
    VS,
    PL,
    MI,
    GE,
    LT,
    GT,
    LE,
}

SR :: bit_field u16 {
    c: bool         | 1,
    v: bool         | 1,
    z: bool         | 1,
    n: bool         | 1,
    x: bool         | 1,
    na1: u8         | 3,
    intr_mask: u8   | 3,
    na2: bool       | 2,
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
@(private="file")
stop: bool
@(private="file")
current_op: u16
@(private="file")
irq_req: u8

cpu_init :: proc()
{
    fmt.println("Cpu init") //Get rid of unused fmt error
    cpu_exception_reset()
}

@(private="file")
cpu_refetch :: proc()
{
    prefetch[2] = cpu_read16_2(pc)
    prefetch[1] = prefetch[2]
    prefetch[2] = cpu_read16_2(pc + 2)
    prefetch[0] = prefetch[1]
}

@(private="file")
cpu_prefetch :: proc()
{
    pc += 2
    prefetch[1] = prefetch[2]
    prefetch[2], _ = (cpu_read16(pc + 2))
    prefetch[0] = prefetch[1]
}

@(private="file")
cpu_fetch :: proc() -> u16
{
    ret := prefetch[2]
    pc += 2
    prefetch[2], _ = cpu_read16(pc + 2)
    return ret
}

cpu_step :: proc() -> u32
{
    if stop {
        return 0
    }
    cpu_decode(prefetch[0])
    if irq_req > 0 {
        cpu_exception_irq(irq_req)
        irq_req = 0
    }
    return cycles
}

cpu_interrupt :: proc(irq: u8)
{
    if irq == 7 || irq > sr.intr_mask {
        irq_req |= irq
    }
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
cpu_get_address :: proc(mode: u16, reg: u16, size: Size, apa: bool = false) -> u32
{
    addr: u32
    switch mode {
        case 2:
            addr = cpu_Areg_get(reg)
        case 3:
            addr = cpu_Areg_get(reg)
            tmp_addr := addr
            switch size {
                case .Byte:
                    if reg == 7 {
                        tmp_addr += 2
                    } else {
                        tmp_addr += 1
                    }
                case .Word:
                    tmp_addr += 2
                case .Long:
                    tmp_addr += 4
            }
            cpu_Areg_set(reg, tmp_addr)
        case 4:
            addr = cpu_Areg_get(reg)
            switch size {
                case .Byte:
                    if reg == 7 {
                        addr -= 2
                    } else {
                        addr -= 1
                    }
                case .Word:
                    addr -= 2
                case .Long:
                    if (addr & 1) == 1 && apa {
                        addr -= 2
                    } else {
                        addr -= 4
                    }
            }
            cpu_Areg_set(reg, addr)
            cpu_idle(2)
        case 5:
            ext1 := i16(cpu_fetch())
            addr = u32(i64(cpu_Areg_get(reg)) + i64(ext1))
        case 6:
            cpu_idle(2)
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
                    cpu_idle(2)
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
                        index_reg = u64(i16(index_reg))
                    }
                    addr = u32(i64(i8(ext1)) + i64(pc) + i64(index_reg))
            }
    }
    return addr
}

@(private="file")
cpu_get_cycles_lea_pea :: proc(mode: u16, reg: u16)
{
    switch mode {
        case 5:
            cycles += 4
        case 6:
            cycles += 8
        case 7:
            switch reg {
                case 0, 2:
                    cycles += 4
                case 1, 3:
                    cycles += 8
            }
    }
}

@(private="file")
cpu_get_cycles_jmp_jsr :: proc(mode: u16, reg: u16)
{
    switch mode {
        case 5:
            cycles += 2//d 16,An
        case 6:
            cycles += 6//(d8,An,Xn)
        case 7:
            switch reg {
                case 0, 2:
                    cycles += 2//(xxx).W  //(d16,PC)
                case 1:
                    cycles += 4//(xxx).L
                case 3:
                    cycles += 6//(d8,PC,Xn)
            }
    }
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
        data = cpu_read8(addr)
    }
    return data
}

@(private="file")
cpu_get_ea_data16 :: proc(mode: u16, reg: u16, addr: u32) -> (u16, bool)
{
    data: u16
    err: bool
    if mode == 0 {
        data = u16(D[reg])
    } else if mode == 1 {
        data = u16(cpu_Areg_get(reg))
    } else if mode == 7 && reg == 4 {
        data = cpu_fetch()
    } else {
        data, err = cpu_read16(addr)
        if err == false {
            return 0, false
        }
    }
    return data, true
}

@(private="file")
cpu_get_ea_data32 :: proc(mode: u16, reg: u16, addr: u32) -> (u32, bool)
{
    data: u32
    err: bool
    if mode == 0 {
        data = D[reg]
    } else if mode == 1 {
        data = cpu_Areg_get(reg)
    } else if mode == 7 && reg == 4 {
        data = u32(cpu_fetch()) << 16
        data |= u32(cpu_fetch())
    } else {
        data, err = cpu_read32(addr)
        if err == false {
            return 0, false
        }
    }
    return data, true
}

@(private="file")
cpu_idle :: proc(idle_cycles: u32)
{
    cycles += idle_cycles
}

@(private="file")
cpu_read8 :: proc(addr: u32) -> (u8)
{
    cycles += 4
    return u8(bus_read(8, addr))
}

@(private="file")
cpu_read16 :: proc(addr: u32) -> (u16, bool)
{
    if (addr & 1) == 1 {
        cpu_exception_addr(.Address, addr, true)
        return 0, false
    }
    value := cpu_read16_2(addr)
    return value, true
}

@(private="file")
cpu_read16_2 :: proc(addr: u32) -> u16
{
    cycles += 4
    value := u16(bus_read(16, addr))
    return value
}

@(private="file")
cpu_read32 :: proc(addr: u32) -> (u32, bool)
{
    if (addr & 1) == 1 {
        cpu_exception_addr(.Address, addr, true)
        return 0, false
    }
    cycles += 8
    return bus_read(32, addr), true
}

@(private="file")
cpu_write8 :: proc(addr: u32, value: u8)
{
    bus_write(8, addr, u32(value))
    cycles += 4
}

@(private="file")
cpu_write16 :: proc(addr: u32, value: u16) -> bool
{
    if (addr & 1) == 1 {
        cpu_exception_addr(.Address, addr, false)
        return false
    }
    bus_write(16, addr, u32(value))
    cycles += 4
    return true
}

@(private="file")
cpu_write32 :: proc(addr: u32, value: u32) -> bool
{
    if (addr & 1) == 1 {
        cpu_exception_addr(.Address, addr, false)
        return false
    }
    bus_write(32, addr, value)
    cycles += 8
    return true
}

@(private="file")
cpu_push32 :: proc(value: u32)
{
    if sr.super {
        ssp -= 4
        cpu_write16(ssp, u16(value >> 16))
        ssp += 2
        cpu_write16(ssp, u16(value&0xFFFF))
        ssp -= 2
    } else {
        usp -= 4
        cpu_write16(usp, u16(value >> 16))
        usp += 2
        cpu_write16(usp, u16(value&0xFFFF))
        usp -= 2
    }
}

@(private="file")
cpu_pc_add :: proc(imm: i32) -> bool
{
    new_pc := u32(i32(pc) + imm)
    pc = new_pc
    if (pc & 1) == 1 {
        pc -= 4
        cpu_exception_addr(.Address, new_pc, true, true)
        return false
    }
    return true
}

@(private="file")
cpu_pc_set :: proc(imm: u32) -> bool
{
    new_pc := imm
    pc = new_pc
    if (pc & 1) == 1 {
        pc -= 4
        cpu_exception_addr(.Address, new_pc, true, true)
        return false
    }
    return true
}

@(private="file")
cpu_cond_get :: proc(cond: Conditional) -> bool
{
    switch cond {
        case .T:
            return true
        case .F:
            return false
        case .HI:
            return !sr.c & !sr.z
        case .LS:
            return sr.c | sr.z
        case .CC:
            return !sr.c
        case .CS:
            return sr.c
        case .NE:
            return !sr.z
        case .EQ:
            return sr.z
        case .VC:
            return !sr.v
        case .VS:
            return sr.v
        case .PL:
            return !sr.n
        case .MI:
            return sr.n
        case .GE:
            return sr.n & sr.v | !sr.n & !sr.v
        case .LT:
            return sr.n & !sr.v | !sr.n & sr.v
        case .GT:
            return sr.n & sr.v & !sr.z | !sr.n & !sr.v & !sr.z
        case .LE:
            return sr.z | sr.n & !sr.v | !sr.n & sr.v
    }
    return false
}

@(private="file")
cpu_get_exc_group :: proc(exc: Exception) -> u8
{
    switch exc {
        case .Reset, .Address, .Bus:
            return 0
        case .Trace, .Interrupt, .Illegal, .Privilege, .Spurious,
             .Uninitialized, .Line1010, .Line1111:
            return 1
        case .Trap, .CHK, .Zero, .TrapV:
            return 2
    }
    return 2
}

@(private="file")
cpu_exception_reset :: proc()
{
    sr.super = true
    sr.trace = 0
    sr.intr_mask = 7
    ssp = bus_read(32, 0x00)
    pc = bus_read(32, 0x04)
    cpu_refetch()
    stop = false
    irq_req = 0
}

@(private="file")
cpu_exception :: proc(exc: Exception)
{
    exc_vec: u32
    tmp_sr := u16(sr)
    sr.super = true
    sr.trace = 0

    cycles += 6
    ssp -= 4
    cpu_write32(ssp, pc)
    ssp -= 2
    cpu_write16(ssp, tmp_sr)
    #partial switch exc {
        case .Illegal:
            exc_vec = 16
        case .Zero:
            exc_vec = 20
            cycles += 4
        case .CHK:
            exc_vec = 24
        case .TrapV:
            exc_vec = 28
        case .Privilege:
            exc_vec = 32
        case .Trace:
            exc_vec = 36
            stop = false
        case .Line1010:
            exc_vec = 40
        case .Line1111:
            exc_vec = 44
        case .Uninitialized:
            exc_vec = 60
            cycles += 10
        case .Spurious:
            exc_vec = 96
            cycles += 10
        case .Trap:
            exc_vec = 128 + (u32(current_op & 0xF) << 2)
    }
    pc, _ = cpu_read32(exc_vec)
    cpu_refetch()
}

@(private="file")
cpu_exception_irq :: proc(irq: u8)
{
    tmp_sr := u16(sr)
    sr.super = true
    sr.trace = 0

    cycles += 14
    ssp -= 4
    cpu_write32(ssp, pc)
    ssp -= 2
    cpu_write16(ssp, tmp_sr)
    exc_vec :u32= 96 + u32(irq * 4)
    stop = false
    pc, _ = cpu_read32(exc_vec)
    cpu_refetch()
}

@(private="file")
cpu_exception_addr :: proc(exc: Exception, addr: u32, rw: bool, i_n: bool = false)
{
    exc_vec: u32
    function_code :u16= 1 + u16(i_n)   //TODO; Check this
    function_code |= (u16(sr.super) << 2)
    tmp_sr := u16(sr)
    sr.super = true
    sr.trace = 0

    cycles += 6
    ssp -= 4
    cpu_write32(ssp, pc)
    ssp -= 2
    cpu_write16(ssp, tmp_sr)
    #partial switch exc {
        case .Bus:
            exc_vec = 8
        case .Address:
            exc_vec = 12
    }
    ssp -= 2
    cpu_write16(ssp, current_op)
    ssp -= 4
    cpu_write32(ssp, addr)
    ssp -= 2
    flags:u16= ((current_op & 0xFFE0))
    flags |= u16(rw) << 4
    flags |= u16(i_n) << 3
    flags |= function_code
    cpu_write16(ssp, flags)
    pc, _ = cpu_read32(exc_vec)
    cpu_refetch()
}

cpu_decode :: proc(opcode: u16) -> u32
{
    current_op = opcode
    cycles = 0
    instrTbl[opcode].function(opcode)
    return cycles
}

cpu_ori_ccr :: proc(opcode: u16) -> bool
{
    imm := u8(cpu_fetch() & 0xFF)
    tmp_sr := u16(sr)
    ccr := u8(tmp_sr) | imm
    tmp_sr &= 0xFF00
    sr = SR(tmp_sr | u16(ccr & 0x1F))
    cpu_idle(8)
    cpu_read16(pc + 2) //Dummy read
    cpu_prefetch()
    return true
}

cpu_ori_sr :: proc(opcode: u16) -> bool
{
    if sr.super {
        imm := cpu_fetch()
        tmp_sr := u16(sr) | imm
        tmp_sr &= 0xA71F
        sr = SR(tmp_sr)
        cpu_idle(8)
        cpu_read16(pc + 2) //Dummy read
        cpu_prefetch()

    } else {
        cpu_exception(.Privilege)
        return false
    }
    return true
}

cpu_andi_ccr :: proc(opcode: u16) -> bool
{
    imm := u8(cpu_fetch() & 0xFF)
    tmp_sr := u16(sr)
    ccr := u8(tmp_sr) & imm
    tmp_sr &= 0xFF00
    sr = SR(tmp_sr | u16(ccr & 0x1F))
    cpu_idle(8)
    cpu_read16(pc + 2) //Dummy read
    cpu_prefetch()
    return true
}

cpu_andi_sr :: proc(opcode: u16) -> bool
{
    if sr.super {
        imm := cpu_fetch()
        tmp_sr := u16(sr) & imm
        tmp_sr &= 0xA71F
        sr = SR(tmp_sr)
        cpu_idle(8)
        cpu_read16(pc + 2) //Dummy read
        cpu_prefetch()
    } else {
        cpu_exception(.Privilege)
        return false
    }
    return true
}

cpu_eori_ccr :: proc(opcode: u16) -> bool
{
    imm := u8(cpu_fetch() & 0xFF)
    tmp_sr := u16(sr)
    ccr := u8(tmp_sr) ~ imm
    tmp_sr &= 0xFF00
    sr = SR(tmp_sr | u16(ccr & 0x1F))
    cpu_idle(8)
    cpu_read16(pc + 2) //Dummy read
    cpu_prefetch()
    return true
}

cpu_eori_sr :: proc(opcode: u16) -> bool
{
    if sr.super {
        imm := cpu_fetch()
        tmp_sr := u16(sr) ~ imm
        tmp_sr &= 0xA71F
        sr = SR(tmp_sr)
        cpu_idle(8)
        cpu_read16(pc + 2) //Dummy read
        cpu_prefetch()
    } else {
        cpu_exception(.Privilege)
        return false
    }
    return true
}

cpu_eori :: proc(opcode: u16) -> bool
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            imm := u8(cpu_fetch())
            if mode == 0 {
                cpu_prefetch()
                data := imm ~ u8(D[reg])
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(data)
                flags8_2(data)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                data := ea_data ~ u8(imm)
                cpu_prefetch()
                cpu_write8(addr, u8(data))
                flags8_2(data)
            }
        case .Word:
            imm := u16(cpu_fetch())
            if mode == 0 {
                cpu_prefetch()
                data := imm ~ u16(D[reg])
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(data)
                flags16_2(data)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data16(mode, reg, addr) or_return
                data := ea_data ~ u16(imm)
                cpu_prefetch()
                cpu_write16(addr, u16(data))
                flags16_2(data)
            }
        case .Long:
            imm := u32(cpu_fetch()) << 16
            imm |= u32(cpu_fetch())
            if mode == 0 {
                cpu_prefetch()
                cpu_idle(4)
                data := imm ~ D[reg]
                D[reg] = data
                flags32_2(data)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data32(mode, reg, addr) or_return
                data := ea_data ~ imm
                cpu_prefetch()
                cpu_write32(addr, data) or_return
                flags32_2(data)
            }
    }
    return true
}

cpu_cmpi :: proc(opcode: u16) -> bool
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            imm := i8(cpu_fetch())
            if mode == 0 {
                cpu_prefetch()
                data, ovf := intrinsics.overflow_sub(i8(D[reg]), i8(imm))
                carry := bool((u16(u8(D[reg])) - u16(u8(imm))) >> 8)
                flags8(data, ovf, carry, false)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                data, ovf := intrinsics.overflow_sub(i8(ea_data), i8(imm))
                cpu_prefetch()
                carry := bool((u16(u8(ea_data)) - u16(u8(imm))) >> 8)
                flags8(data, ovf, carry, false)
            }
        case .Word:
            imm := i16(cpu_fetch())
            if mode == 0 {
                cpu_prefetch()
                data, ovf := intrinsics.overflow_sub(i16(D[reg]), i16(imm))
                carry := bool((u32(u16(D[reg])) - u32(u16(imm))) >> 16)
                flags16(data, ovf, carry, false)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data16(mode, reg, addr) or_return
                data, ovf := intrinsics.overflow_sub(i16(ea_data), i16(imm))
                cpu_prefetch()
                carry := bool((u32(u16(ea_data)) - u32(u16(imm))) >> 16)
                flags16(data, ovf, carry, false)
            }
        case .Long:
            imm := i32(cpu_fetch()) << 16
            imm |= i32(cpu_fetch())
            if mode == 0 {
                cpu_prefetch()
                cpu_idle(2)
                data, ovf := intrinsics.overflow_sub(i32(D[reg]), i32(imm))
                carry := bool((u64(u32(D[reg])) - u64(u32(imm))) >> 32)
                flags32(data, ovf, carry, false)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data32(mode, reg, addr) or_return
                data, ovf := intrinsics.overflow_sub(i32(ea_data), i32(imm))
                cpu_prefetch()
                carry := bool((u64(u32(ea_data)) - u64(u32(imm))) >> 32)
                flags32(data, ovf, carry, false)
            }
    }
    return true
}

cpu_movea :: proc(opcode: u16) -> bool
{
    size := (opcode >> 12) & 3
    reg := (opcode >> 9) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7
    ea_data: u32

    switch size {
        case 3: //Word
            addr := cpu_get_address(mode, reg2, .Word)
            ea_data = u32(i32(i16(cpu_get_ea_data16(mode, reg2, addr) or_return)))
        case 2: //Long
            addr := cpu_get_address(mode, reg2, .Long)
            ea_data = cpu_get_ea_data32(mode, reg2, addr) or_return
    }
    cpu_Areg_set(reg, ea_data)
    cpu_prefetch()
    return true
}

cpu_move :: proc(opcode: u16) -> bool
{
    size := (opcode >> 12) & 3
    reg := (opcode >> 9) & 7
    mode := (opcode >> 6) & 7
    mode2 := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    switch size {
        case 1:
            addr2 := cpu_get_address(mode2, reg2, .Byte)
            ea_data := cpu_get_ea_data8(mode2, reg2, addr2)
            addr := cpu_get_address(mode, reg, .Byte)
            if mode == 0 {
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(ea_data)
            } else {
                cpu_write8(addr, ea_data)
            }
            sr.v = false
            sr.c = false
            sr.n = bool((ea_data >> 7) & 1)
            sr.z = bool(ea_data == 0)
        case 3:
            addr2 := cpu_get_address(mode2, reg2, .Word)
            ea_data := cpu_get_ea_data16(mode2, reg2, addr2) or_return
            sr.v = false
            sr.c = false
            sr.n = bool((ea_data >> 15) & 1)
            sr.z = bool(ea_data == 0)
            addr := cpu_get_address(mode, reg, .Word)

            if (addr & 1) == 1 {
                if mode == 3 {
                    cpu_Areg_set(reg, A[reg] - 2)
                }
                if mode == 4 {
                    cycles += 2
                    pc += 2
                }
                cpu_exception_addr(.Address, addr, false)
                return false
            }
            if mode == 0 {
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(ea_data)
            } else {
                cpu_write16(addr, ea_data)
            }
        case 2:
            addr2 := cpu_get_address(mode2, reg2, .Long)
            ea_data := cpu_get_ea_data32(mode2, reg2, addr2) or_return
            sr.v = false
            sr.c = false
            sr.n = bool((ea_data >> 31) & 1)
            sr.z = bool(ea_data == 0)
            addr := cpu_get_address(mode, reg, .Long, true)

            if (addr & 1) == 1 {
                if mode == 3 {
                    cpu_Areg_set(reg, A[reg] - 4)
                }
                if mode == 4 {
                    cycles += 2
                    pc += 2
                }
                cpu_exception_addr(.Address, addr, false)
                return false
            }
            if mode == 0 {
                D[reg] = u32(ea_data)
            } else {
                cpu_write32(addr, ea_data)
            }
    }
    if mode == 4 {
        cycles -= 2
    }
    cpu_prefetch()
    return true
}

cpu_addi :: proc(opcode: u16) -> bool
{
    return cpu_alui(opcode, .Add)
}

cpu_subi :: proc(opcode: u16) -> bool
{
    return cpu_alui(opcode, .Sub)
}

cpu_andi :: proc(opcode: u16) -> bool
{
    return cpu_alui(opcode, .And)
}

cpu_ori :: proc(opcode: u16) -> bool
{
    return cpu_alui(opcode, .Or)
}

cpu_alui :: proc(opcode: u16, op: Operation) -> bool
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    ovf: bool

    switch size {
        case .Byte:
            data: i8
            imm := i8(cpu_fetch())
            if mode == 0 {
                cpu_prefetch()
                switch op {
                    case .Add:
                        data, ovf = intrinsics.overflow_add(i8(imm), i8(D[reg]))
                        carry := bool((u16(u8(imm)) + u16(u8(D[reg]))) >> 8)
                        flags8(data, ovf, carry)
                    case .Sub:
                        data, ovf = intrinsics.overflow_sub(i8(D[reg]), i8(imm))
                        carry := bool((u16(u8(D[reg])) - u16(u8(imm))) >> 8)
                        flags8(data, ovf, carry)
                    case .And:
                        data = i8(imm & i8(D[reg]))
                        flags8_2(u8(data))
                    case .Or:
                        data = i8(imm | i8(D[reg]))
                        flags8_2(u8(data))
                }
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(u8(data))
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                switch op {
                    case .Add:
                        data, ovf = intrinsics.overflow_add(i8(ea_data), i8(imm))
                        carry := bool((u16(ea_data) + u16(u8(imm))) >> 8)
                        flags8(data, ovf, carry)
                    case .Sub:
                        data, ovf = intrinsics.overflow_sub(i8(ea_data), i8(imm))
                        carry := bool((u16(ea_data) - u16(u8(imm))) >> 8)
                        flags8(data, ovf, carry)
                    case .And:
                        data = i8(ea_data) & imm
                        flags8_2(u8(data))
                    case .Or:
                        data = i8(ea_data) | imm
                        flags8_2(u8(data))
                }
                cpu_prefetch()
                cpu_write8(addr, u8(data))
            }
        case .Word:
            data: i16
            imm := i16(cpu_fetch())
            if mode == 0 {
                cpu_prefetch()
                switch op {
                    case .Add:
                        data, ovf = intrinsics.overflow_add(i16(imm), i16(D[reg]))
                        carry := bool((u32(u16(imm)) + u32(u16(D[reg]))) >> 16)
                        flags16(data, ovf, carry)
                    case .Sub:
                        data, ovf = intrinsics.overflow_sub(i16(D[reg]), i16(imm))
                        carry := bool((u32(u16(D[reg])) - u32(u16(imm))) >> 16)
                        flags16(data, ovf, carry)
                    case .And:
                        data = imm & i16(D[reg])
                        flags16_2(u16(data))
                    case .Or:
                        data = imm | i16(D[reg])
                        flags16_2(u16(data))
                }
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(u16(data))
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data16(mode, reg, addr) or_return
                switch op {
                    case .Add:
                        data, ovf = intrinsics.overflow_add(i16(ea_data), i16(imm))
                        carry := bool((u32(ea_data) + u32(u16(imm))) >> 16)
                        flags16(data, ovf, carry)
                    case .Sub:
                        data, ovf = intrinsics.overflow_sub(i16(ea_data), i16(imm))
                        carry := bool((u32(ea_data) - u32(u16(imm))) >> 16)
                        flags16(data, ovf, carry)
                    case .And:
                        data = i16(ea_data & u16(imm))
                        flags16_2(u16(data))
                    case .Or:
                        data = i16(ea_data | u16(imm))
                        flags16_2(u16(data))
                }
                cpu_prefetch()
                cpu_write16(addr, u16(data))
            }
        case .Long:
            data: i32
            imm := i32(cpu_fetch()) << 16
            imm |= i32(cpu_fetch())
            if mode == 0 {
                cpu_prefetch()
                switch op {
                    case .Add:
                        data, ovf = intrinsics.overflow_add(i32(imm), i32(D[reg]))
                        carry := bool((u64(u32(imm)) + u64(u32(D[reg]))) >> 32)
                        flags32(data, ovf, carry)
                    case .Sub:
                        data, ovf = intrinsics.overflow_sub(i32(D[reg]), i32(imm))
                        carry := bool((u64(u32(D[reg])) - u64(u32(imm))) >> 32)
                        flags32(data, ovf, carry)
                    case .And:
                        data = imm & i32(D[reg])
                        flags32_2(u32(data))
                    case .Or:
                        data = imm | i32(D[reg])
                        flags32_2(u32(data))
                }
                D[reg] = u32(data)
                cpu_idle(4)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data32(mode, reg, addr) or_return
                switch op {
                    case .Add:
                        data, ovf = intrinsics.overflow_add(i32(ea_data), i32(imm))
                        carry := bool((u64(ea_data) + u64(u32(imm))) >> 32)
                        flags32(data, ovf, carry)
                    case .Sub:
                        data, ovf = intrinsics.overflow_sub(i32(ea_data), i32(imm))
                        carry := bool((u64(ea_data) - u64(u32(imm))) >> 32)
                        flags32(data, ovf, carry)
                    case .And:
                        data = i32(ea_data) & imm
                        flags32_2(u32(data))
                    case .Or:
                        data = i32(ea_data) | imm
                        flags32_2(u32(data))
                }
                cpu_prefetch()
                cpu_write32(addr, u32(data)) or_return
            }
    }
    return true
}

cpu_btst_mem :: proc(opcode: u16) -> bool
{
    return cpu_bit(opcode, true, .Test)
}

cpu_bchg_mem :: proc(opcode: u16) -> bool
{
    return cpu_bit(opcode, true, .Change)
}

cpu_bclr_mem :: proc(opcode: u16) -> bool
{
    return cpu_bit(opcode, true, .Clear)
}

cpu_bset_mem :: proc(opcode: u16) -> bool
{
    return cpu_bit(opcode, true, .Set)
}

cpu_btst_reg :: proc(opcode: u16) -> bool
{
    return cpu_bit(opcode, false, .Test)
}

cpu_bchg_reg :: proc(opcode: u16) -> bool
{
    return cpu_bit(opcode, false, .Change)
}

cpu_bclr_reg :: proc(opcode: u16) -> bool
{
    return cpu_bit(opcode, false, .Clear)
}

cpu_bset_reg :: proc(opcode: u16) -> bool
{
    return cpu_bit(opcode, false, .Set)
}

cpu_bit :: proc(opcode: u16, mem: bool, bitop: BitOp) -> bool
{
    reg2 := (opcode >> 9) & 7
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    shift: u32

    if mem {
        shift = u32(u8(cpu_fetch()))
    } else {
        shift = D[reg2]
    }

    if mode == 0 {
        shift = shift % 32
        addr := cpu_get_address(mode, reg, .Long)
        ea_data := cpu_get_ea_data32(mode, reg, addr) or_return
        sr.z = !(bool((ea_data >> shift) & 1))
        cpu_prefetch()
        switch bitop {
            case .Set:
                ea_data |= (1 << shift)
                D[reg] = ea_data
                if shift < 16 {
                    cpu_idle(2)
                } else {
                    cpu_idle(4)
                }
            case .Clear:
                ea_data &= (0xFFFFFFFF ~ (1 << shift))
                D[reg] = ea_data
                if shift < 16 {
                    cpu_idle(4)
                } else {
                    cpu_idle(6)
                }
            case .Change:
                ea_data ~= (1 << shift)
                D[reg] = ea_data
                if shift < 16 {
                    cpu_idle(2)
                } else {
                    cpu_idle(4)
                }
            case .Test:
                cpu_idle(2)
        }
    } else {
        shift = u32(u8(shift) % 8)
        addr := cpu_get_address(mode, reg, .Byte)
        ea_data := cpu_get_ea_data8(mode, reg, addr)
        sr.z = !(bool((ea_data >> shift) & 1))
        cpu_prefetch()
        switch bitop {
            case .Set:
                ea_data |= (1 << shift)
                cpu_write8(addr, ea_data)
            case .Clear:
                ea_data &= (0xFF ~ (1 << shift))
                cpu_write8(addr, ea_data)
            case .Change:
                ea_data ~= (1 << shift)
                cpu_write8(addr, ea_data)
            case .Test:
                //Do nothing
        }
        if mode == 7 && reg == 4 && mem == false {
            cpu_idle(2)
        }
    }
    return true
}

cpu_movep :: proc(opcode: u16) -> bool
{
    reg2 := (opcode >> 9) & 7
    mode := (opcode >> 6) & 3
    reg := (opcode >> 0) & 7

    switch mode {
        case 0:
            addr := cpu_get_address(5, reg, .Word)
            data1 := cpu_get_ea_data8(5, reg, addr)
            data2 := cpu_get_ea_data8(5, reg, addr + 2)
            D[reg2] &= 0xFFFF0000
            D[reg2] |= u32(u16(data2) | (u16(data1) << 8))
        case 1:
            addr := cpu_get_address(5, reg, .Word)
            data1 := cpu_get_ea_data8(5, reg, addr)
            data2 := cpu_get_ea_data8(5, reg, addr + 2)
            data3 := cpu_get_ea_data8(5, reg, addr + 4)
            data4 := cpu_get_ea_data8(5, reg, addr + 6)
            D[reg2] = u32(data4) | (u32(data3) << 8) | (u32(data2) << 16) | (u32(data1) << 24)
        case 2:
            data := u16(D[reg2])
            addr := cpu_get_address(5, reg, .Word)
            cpu_write8(addr, u8(data >> 8))
            cpu_write8(addr + 2, u8(data))
        case 3:
            data := D[reg2]
            addr := cpu_get_address(5, reg, .Word)
            cpu_write8(addr, u8(data >> 24))
            cpu_write8(addr + 2, u8(data >> 16))
            cpu_write8(addr + 4, u8(data >> 8))
            cpu_write8(addr + 6, u8(data))
    }

    cpu_prefetch()
    return true
}

cpu_move_from_sr :: proc(opcode: u16) -> bool
{
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    if mode == 0 {
        D[reg] &= 0xFFFF0000
        D[reg] |= u32(u16(sr))
        cpu_prefetch()
        cpu_idle(2)
    } else {
        addr := cpu_get_address(mode, reg, .Word)
        cpu_get_ea_data16(mode, reg, addr) or_return
        cpu_prefetch()
        cpu_write16(addr, u16(sr))
    }
    return true
}

cpu_negx :: proc(opcode: u16) -> bool
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            addr := cpu_get_address(mode, reg, size)
            ea_data := cpu_get_ea_data8(mode, reg, addr)

            res := 0 - ea_data - u8(sr.x)
            if mode == 0 {
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(res)
            } else {
                cpu_write8(addr, u8(res))
            }
            sr.c = bool((ea_data | res) >> 7)
            sr.v = bool((ea_data & res) >> 7)
            if res != 0 {
                sr.z = false
            }
            sr.n = bool(res >> 7)
            sr.x = sr.c
        case .Word:
            addr := cpu_get_address(mode, reg, size)
            ea_data := cpu_get_ea_data16(mode, reg, addr) or_return

            res := 0 - ea_data - u16(sr.x)
            if mode == 0 {
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(res)
            } else {
                cpu_write16(addr, u16(res))
            }
            sr.c = bool((ea_data | res) >> 15)
            sr.v = bool((ea_data & res) >> 15)
            if res != 0 {
                sr.z = false
            }
            sr.n = bool(res >> 15)
            sr.x = sr.c
        case .Long:
            addr := cpu_get_address(mode, reg, size)
            ea_data := cpu_get_ea_data32(mode, reg, addr) or_return

            res := 0 - ea_data - u32(sr.x)
            if mode == 0 {
                D[reg] = res
                cycles += 2
            } else {
                cpu_write32(addr, res)
            }
            sr.c = bool((ea_data | res) >> 31)
            sr.v = bool((ea_data & res) >> 31)
            if res != 0 {
                sr.z = false
            }
            sr.n = bool(res >> 31)
            sr.x = sr.c
    }

    cpu_prefetch()
    return true
}

cpu_move_ccr :: proc(opcode: u16) -> bool
{
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg, .Word)
    ea_data := cpu_get_ea_data16(mode, reg, addr) or_return
    ea_data&= 0x1F
    tmp_sr := u16(sr)
    tmp_sr &= 0xFF00
    tmp_sr |= u16(ea_data)
    sr = SR(tmp_sr)
    cpu_idle(4)
    cpu_read16(pc + 2)  //Dummy read
    cpu_prefetch()
    return true
}

cpu_move_to_sr :: proc(opcode: u16) -> bool
{
    if sr.super {
        mode := (opcode >> 3) & 7
        reg := (opcode >> 0) & 7

        addr := cpu_get_address(mode, reg, .Word)
        ea_data := cpu_get_ea_data16(mode, reg, addr) or_return
        ea_data &= 0xA71F
        sr = SR(ea_data)
    } else {
        cpu_exception(.Privilege)
        return false
    }
    cpu_idle(4)
    cpu_read16(pc + 2)  //Dummy read
    cpu_prefetch()
    return true
}

cpu_clr :: proc(opcode: u16) -> bool
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            if mode == 0 {
                D[reg] = D[reg] & 0xFFFFFF00
                cpu_prefetch()
            } else {
                addr := cpu_get_address(mode, reg, size)
                cpu_get_ea_data8(mode, reg, addr)
                cpu_prefetch()
                cpu_write8(addr, 0)
            }
        case .Word:
            if mode == 0 {
                D[reg] = D[reg] & 0xFFFF0000
                cpu_prefetch()
            } else {
                addr := cpu_get_address(mode, reg, size)
                cpu_get_ea_data16(mode, reg, addr) or_return
                cpu_prefetch()
                cpu_write16(addr, 0)
            }
        case .Long:
            if mode == 0 {
                D[reg] = 0
                cpu_prefetch()
                cpu_idle(2)
            } else {
                addr := cpu_get_address(mode, reg, size)
                cpu_get_ea_data32(mode, reg, addr) or_return
                cpu_prefetch()
                cpu_write32(addr, 0)
            }
    }
    sr.n = false
    sr.z = true
    sr.v = false
    sr.c = false
    return true
}

cpu_neg :: proc(opcode: u16) -> bool
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            if mode == 0 {
                data, ovf := intrinsics.overflow_sub(i8(0), i8(D[reg]))
                carry := bool((u16(0) - u16(u8(D[reg]))) >> 8)
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(u8(data))
                flags8(data, ovf, carry)
                cpu_prefetch()
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                data, ovf := intrinsics.overflow_sub(i8(0), i8(ea_data))
                carry := bool((u16(0) - u16(u8(ea_data))) >> 8)
                cpu_prefetch()
                cpu_write8(addr, u8(data))
                flags8(data, ovf, carry)
            }
        case .Word:
            if mode == 0 {
                data, ovf := intrinsics.overflow_sub(i16(0), i16(D[reg]))
                carry := bool((u32(0) - u32(u16(D[reg]))) >> 16)
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(u16(data))
                flags16(data, ovf, carry)
                cpu_prefetch()
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data16(mode, reg, addr) or_return
                data, ovf := intrinsics.overflow_sub(i16(0), i16(ea_data))
                carry := bool((u32(0) - u32(u16(ea_data))) >> 8)
                cpu_prefetch()
                cpu_write16(addr, u16(data))
                flags16(data, ovf, carry)
            }
        case .Long:
            if mode == 0 {
                data, ovf := intrinsics.overflow_sub(i32(0), i32(D[reg]))
                carry := bool((u64(0) - u64(u32(D[reg]))) >> 32)
                D[reg] = u32(data)
                flags32(data, ovf, carry)
                cpu_prefetch()
                cpu_idle(2)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data32(mode, reg, addr) or_return
                data, ovf := intrinsics.overflow_sub(i32(0), i32(ea_data))
                carry := bool((u64(0) - u64(u32(ea_data))) >> 32)
                cpu_prefetch()
                cpu_write32(addr, u32(data)) or_return
                flags32(data, ovf, carry)
            }
    }
    return true
}

cpu_not :: proc(opcode: u16) -> bool
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            if mode == 0 {
                data := ~u8(D[reg])
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(data)
                flags8_2(data)
                cpu_prefetch()
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                data := ~ea_data
                cpu_prefetch()
                cpu_write8(addr, data)
                flags8_2(data)
            }
        case .Word:
            if mode == 0 {
                data := ~u16(D[reg])
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(data)
                flags16_2(data)
                cpu_prefetch()
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data16(mode, reg, addr) or_return
                data := ~ea_data
                cpu_prefetch()
                cpu_write16(addr, data)
                flags16_2(data)
            }
        case .Long:
            if mode == 0 {
                data :=  ~u32(D[reg])
                D[reg] = data
                flags32_2(data)
                cpu_prefetch()
                cpu_idle(2)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data32(mode, reg, addr) or_return
                data := ~ea_data
                cpu_prefetch()
                cpu_write32(addr, data) or_return
                flags32_2(data)
            }
    }
    return true
}

cpu_ext :: proc(opcode: u16) -> bool
{
    mode := (opcode >> 6) & 7
    reg := opcode & 7

    switch mode {
        case 2:
            data := u16(i8(D[reg]))
            D[reg] &= 0xFFFF0000
            D[reg] |= u32(data)
            flags16_2(data)
        case 3:
            data := u32(i16(D[reg]))
            D[reg] = data
            flags32_2(data)
    }
    cpu_prefetch()
    return true
}

cpu_nbcd :: proc(opcode: u16) -> bool
{
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg, .Byte)
    ea_data := cpu_get_ea_data8(mode, reg, addr)

    dd := 0 - ea_data - u8(sr.x)
    bc := (ea_data | dd) & 0x88
    corf := bc - (bc >> 2)
    res := dd - corf

    if mode == 0 {
        cycles += 2
        D[reg] &= 0xFFFFFF00
        D[reg] |= u32(res)
    } else {
        cpu_write8(addr, res)
    }
    sr.c = bool((bc | (~dd & res)) >> 7)
    sr.v = bool((dd & ~res) >> 7)
    if res != 0 {
        sr.z = false
    }
    sr.n = bool(res >> 7)
    sr.x = sr.c
    cpu_prefetch()
    return true
}

cpu_swap :: proc(opcode: u16) -> bool
{
    reg := opcode & 7

    lower := (D[reg] & 0x0000FFFF) << 16
    upper := (D[reg] & 0xFFFF0000) >> 16
    data := lower | upper
    D[reg] = data
    flags32_2(data)
    cpu_prefetch()
    return true
}

cpu_pea :: proc(opcode: u16) -> bool
{
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg, .Long)
    cycles = 0
    cpu_push32(addr)
    cpu_get_cycles_lea_pea(mode, reg)
    cpu_prefetch()
    return true
}

cpu_illegal :: proc(opcode: u16) -> bool
{
    cpu_exception(.Illegal)
    return false
}

cpu_tas :: proc(opcode: u16) -> bool
{
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg, .Byte)
    ea_data := cpu_get_ea_data8(mode, reg, addr)
    flags8_2(ea_data)
    ea_data |= 0x80
    if mode == 0 {
        D[reg] &= 0xFFFFFF00
        D[reg] |= u32(ea_data)
    } else {
        cpu_write8(addr, ea_data)
        cpu_idle(2)
    }
    cpu_prefetch()
    return true
}

cpu_tst :: proc(opcode: u16) -> bool
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    addr := cpu_get_address(mode, reg, size)

    switch size {
        case .Byte:
            ea_data := cpu_get_ea_data8(mode, reg, addr)
            flags8_2(ea_data)
        case .Word:
            ea_data := cpu_get_ea_data16(mode, reg, addr) or_return
            flags16_2(ea_data)
        case .Long:
            ea_data := cpu_get_ea_data32(mode, reg, addr) or_return
            flags32_2(ea_data)
    }
    cpu_prefetch()
    return true
}

cpu_trap :: proc(opcode: u16) -> bool
{
    pc += 2 //Point to the next instruction
    cpu_exception(.Trap)
    return true
}

cpu_link :: proc(opcode: u16) -> bool
{
    reg := opcode & 7
    ssp -= 4
    areg := cpu_Areg_get(reg)
    tmp_sp := cpu_fetch()
    cpu_write16(ssp, u16(areg >> 16))
    cpu_write16(ssp + 2, u16(areg & 0xFFFF))
    cpu_Areg_set(reg, ssp)
    ssp += u32(i32(i16(tmp_sp)))
    cpu_prefetch()
    return true
}

cpu_unlk :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 0) & 7
    ssp = cpu_Areg_get(reg)
    value := cpu_read32(ssp) or_return
    cpu_Areg_set(reg, value)
    if reg != 7 {   //TODO: Why?
        ssp += 4
    }
    cpu_prefetch()
    return true
}

cpu_move_usp :: proc(opcode: u16) -> bool
{
    if sr.super {
        dir := (opcode >> 3) & 1
        reg := (opcode >> 0) & 7
        switch dir {
            case 0:
                usp = cpu_Areg_get(reg)
            case 1:
                cpu_Areg_set(reg, usp)
        }
    } else {
        cpu_exception(.Privilege)
        return false
    }
    cpu_prefetch()
    return true
}

cpu_reset :: proc(opcode: u16) -> bool
{
    //TODO: Reset all external devices?
    if sr.super {
        cpu_idle(4)
        cpu_idle(124)
    } else {
        cpu_exception(.Privilege)
        return false
    }
    cpu_prefetch()
    return true
}

cpu_nop :: proc(opcode: u16) -> bool
{
    cpu_prefetch()
    return true
}

cpu_stop :: proc(opcode: u16) -> bool
{
    if sr.super {
        sr = SR(cpu_fetch())
        cpu_idle(4)
        stop = true
    } else {
        cpu_exception(.Privilege)
        return false
    }
    cpu_prefetch()
    return true
}

cpu_rte :: proc(opcode: u16) -> bool
{
    if sr.super {
        new_pc := u32(cpu_read16_2(ssp + 2)) << 16
        sr = SR(cpu_read16_2(ssp) & 0xA71F)
        ssp += 4
        new_pc |= u32(cpu_read16_2(ssp))
        ssp += 2
        cpu_pc_set(new_pc) or_return
    } else {
        cpu_exception(.Privilege)
        return false
    }
    cpu_refetch()
    return true
}

cpu_rts :: proc(opcode: u16) -> bool
{
    tmp_pc, _ := cpu_read32(ssp)
    ssp += 4
    cpu_pc_set(tmp_pc) or_return
    cpu_refetch()
    return true
}

cpu_trapv :: proc(opcode: u16) -> bool
{
    if sr.v {
        pc += 2 //Point to the next instruction
        cpu_exception(.TrapV)
        return false
    }
    cpu_prefetch()
    return true
}

cpu_rtr :: proc(opcode: u16) -> bool
{
    tmp_pc := u32(cpu_read16_2(ssp + 2)) << 16
    sr &= SR(0xFF00)
    sr |= SR(cpu_read16_2(ssp) & 0x1F)
    ssp += 4
    tmp_pc |= u32(cpu_read16_2(ssp))
    ssp += 2
    cpu_pc_set(tmp_pc) or_return
    cpu_refetch()
    return true
}

cpu_jsr :: proc(opcode: u16) -> bool
{
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg, .Long)
    cycles = 0
    cpu_get_cycles_jmp_jsr(mode, reg)
    if (addr & 1) == 0 {
        ssp -= 4
        bus_write(32, ssp, pc + 2)
    }
    cpu_pc_set(addr) or_return
    cycles += 8
    cpu_refetch()
    return true
}

cpu_jmp :: proc(opcode: u16) -> bool
{
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg, .Long)
    if (mode == 7 && reg == 0) || (mode == 7 && reg == 2) || mode == 5 {
        cycles -= 2
    }
    if (mode == 7 && reg == 1) {
        cycles -= 4
    }
    cpu_pc_set(addr) or_return
    cycles = 0
    cpu_get_cycles_jmp_jsr(mode, reg)
    cpu_refetch()
    return true
}

cpu_movem :: proc(opcode: u16) -> bool
{
    dr := (opcode >> 10) & 1
    size := (opcode >> 6) & 1
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    list := cpu_fetch()
    addr := cpu_get_address(mode, reg, .Word)

    switch size {
        case 0:
            if dr == 1 {
                a := u8(list >> 8)
                d := u8(list)
                for i:u16=0; i < 8; i+=1 {
                    if ((d >> i) & 1) == 1 {
                        data := i32(i16(cpu_get_ea_data16(mode, reg, addr) or_return))
                        D[i] = u32(data)
                        addr += 2
                    }
                }
                for j:u16=0; j < 8; j+=1 {
                    if ((a >> j) & 1) == 1 {
                        data := i32(i16(cpu_get_ea_data16(mode, reg, addr) or_return))
                        cpu_Areg_set(j, u32(data))
                        addr += 2
                    }
                }
                if mode == 3 {
                    cpu_Areg_set(reg, addr)
                }
            } else {
                if mode == 4 {
                    cycles -= 2
                }
                if (addr & 1) == 1 {
                    if mode == 4 {
                        cpu_Areg_set(reg, A[reg] + 2)
                    }
                    cpu_exception_addr(.Address, addr, false)
                    return false
                }
                if mode == 4 {
                    d := u8(list >> 8)
                    a := u8(list)
                    addr += 2
                    orig_addr := addr
                    for j:u16=0; j < 8; j+=1 {
                        if ((a >> j) & 1) == 1 {
                            addr -= 2
                            cpu_Areg_set(reg, addr)
                            data := cpu_Areg_get(7 - j)
                            if (7 - j) == reg {
                                cpu_write16(addr, u16(orig_addr))
                            } else {
                                cpu_write16(addr, u16(data))
                            }
                        }
                    }
                    for i:u16=0; i < 8; i+=1 {
                        if ((d >> i) & 1) == 1 {
                            addr -= 2
                            cpu_Areg_set(reg, addr)
                            cpu_write16(addr, u16(D[7 - i]))
                        }
                    }
                } else {
                    a := u8(list >> 8)
                    d := u8(list)
                    for i:u16=0; i < 8; i+=1 {
                        if ((d >> i) & 1) == 1 {
                            cpu_write16(addr, u16(D[i]))
                            addr += 2
                        }
                    }
                    for j:u16=0; j < 8; j+=1 {
                        if ((a >> j) & 1) == 1 {
                            cpu_write16(addr, u16(cpu_Areg_get(j)))
                            addr += 2
                        }
                    }
                }
                cycles -= 4
            }
        case 1:
            if dr == 1 {
                a := u8(list >> 8)
                d := u8(list)
                for i:u16=0; i < 8; i+=1 {
                    if ((d >> i) & 1) == 1 {
                        data := i32(cpu_get_ea_data32(mode, reg, addr) or_return)
                        D[i] = u32(data)
                        addr += 4
                    }
                }
                for j:u16=0; j < 8; j+=1 {
                    if ((a >> j) & 1) == 1 {
                        data := i32(cpu_get_ea_data32(mode, reg, addr) or_return)
                        cpu_Areg_set(j, u32(data))
                        addr += 4
                        if reg == j && mode == 3 {
                            cpu_Areg_set(reg, addr+12)
                        }
                    }
                }
                if mode == 3 {
                    cpu_Areg_set(reg, addr)
                }
            } else {
                if (addr & 1) == 1 {
                    if mode == 4 {
                        cpu_Areg_set(reg, A[reg] + 2)
                        cycles -= 2
                    }
                    cpu_exception_addr(.Address, addr, false)
                    return false
                }
                if mode == 4 {
                    cycles -= 2
                    d := u8(list >> 8)
                    a := u8(list)
                    addr += 2
                    orig_addr := addr
                    for j:u16=0; j < 8; j+=1 {
                        if ((a >> j) & 1) == 1 {
                            addr -= 4
                            cpu_Areg_set(reg, addr)
                            data := cpu_Areg_get(7 - j)
                            if (7 - j) == reg {
                                cpu_write32(addr, orig_addr)
                            } else {
                                cpu_write32(addr, data)
                            }
                        }
                    }
                    for i:u16=0; i < 8; i+=1 {
                        if ((d >> i) & 1) == 1 {
                            addr -= 4
                            cpu_Areg_set(reg, addr)
                            cpu_write32(addr, D[7 - i])
                        }
                    }
                } else {
                    a := u8(list >> 8)
                    d := u8(list)
                    for i:u16=0; i < 8; i+=1 {
                        if ((d >> i) & 1) == 1 {
                            cpu_write32(addr, D[i])
                            addr += 4
                        }
                    }
                    for j:u16=0; j < 8; j+=1 {
                        if ((a >> j) & 1) == 1 {
                            cpu_write32(addr, cpu_Areg_get(j))
                            addr += 4
                        }
                    }
                }
                cycles -= 4
            }
    }
    cycles += 4
    cpu_prefetch()
    return true
}

cpu_lea :: proc(opcode: u16) -> bool
{
    reg2 := (opcode >> 9) & 7
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg, .Long)
    cpu_Areg_set(reg2, addr)
    cycles = 0
    cpu_get_cycles_lea_pea(mode, reg)
    cpu_prefetch()
    return true
}

cpu_chk :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg2, .Word)
    ea_data := i16(cpu_get_ea_data16(mode, reg2, addr) or_return)
    cpu_prefetch()
    data := i16(D[reg])
    sr.z = false
    sr.v = false
    sr.c = false

    if data < 0 || data > ea_data {
        if data < 0 {
            sr.n = true
        }
        else if data > ea_data {
            sr.n = false
        }
        if data > ea_data {
            cpu_exception(.CHK)
        } else {
            cycles += 2
            cpu_exception(.CHK)
        }
        return false
    }
    cpu_idle(6)
    return true
}

cpu_addq :: proc(opcode: u16) -> bool
{
    data := (opcode >> 9) & 7
    if data == 0 {
        data = 8
    }
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            if mode == 0 {
                data2, ovf := intrinsics.overflow_add(i8(data), i8(D[reg]))
                carry := bool((u16(data) + u16(u8(D[reg]))) >> 8)
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(u8(data2))
                cpu_prefetch()
                flags8(data2, ovf, carry)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                cpu_prefetch()
                data2, ovf := intrinsics.overflow_add(i8(data), i8(ea_data))
                cpu_write8(addr, u8(data2))
                carry := bool((u16(data) + u16(u8(ea_data))) >> 8)
                flags8(data2, ovf, carry)
            }
        case .Word:
            if mode == 0 {
                data2, ovf := intrinsics.overflow_add(i16(data), i16(D[reg]))
                carry := bool((u32(data) + u32(u16(D[reg]))) >> 16)
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(u16(data2))
                cpu_prefetch()
                flags16(data2, ovf, carry)
            } else if mode == 1 {
                areg := cpu_Areg_get(reg)
                data := u32(u16(i16(data) + i16(areg)))
                areg &= 0xFFFF0000
                areg |= data
                cpu_Areg_set(reg, areg)
                cpu_prefetch()
                cpu_idle(4)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data16(mode, reg, addr) or_return
                data2, ovf := intrinsics.overflow_add(i16(data), i16(ea_data))
                cpu_prefetch()
                cpu_write16(addr, u16(data2))
                carry := bool((u32(data) + u32(u16(ea_data))) >> 16)
                flags16(data2, ovf, carry)
            }
        case .Long:
            if mode == 0 {
                data2, ovf := intrinsics.overflow_add(i32(data), i32(D[reg]))
                carry := bool((u64(data) + u64(u32(D[reg]))) >> 32)
                D[reg] = u32(data2)
                cpu_prefetch()
                cpu_idle(4)
                flags32(data2, ovf, carry)
            } else if mode == 1 {
                areg := cpu_Areg_get(reg)
                data := u32(i32(data) + i32(areg))
                areg = data
                cpu_Areg_set(reg, areg)
                cpu_prefetch()
                cpu_idle(2)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data32(mode, reg, addr) or_return
                data2, ovf := intrinsics.overflow_add(i32(data), i32(ea_data))
                cpu_prefetch()
                cpu_write32(addr, u32(data2)) or_return
                carry := bool((u64(data) + u64(u32(ea_data))) >> 32)
                flags32(data2, ovf, carry)
            }
    }
    return true
}

cpu_subq :: proc(opcode: u16) -> bool
{
    data := u8((opcode >> 9) & 7)
    if data == 0 {
        data = 8
    }
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            if mode == 0 {
                data2, ovf := intrinsics.overflow_sub(i8(D[reg]), i8(data))
                carry := bool((u16(u8(D[reg])) - u16(data)) >> 8)
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(u8(data2))
                cpu_prefetch()
                flags8(data2, ovf, carry)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                data2, ovf := intrinsics.overflow_sub(i8(ea_data), i8(data))
                cpu_prefetch()
                cpu_write8(addr, u8(data2))
                carry := bool((u16(ea_data) - u16(data)) >> 8)
                flags8(data2, ovf, carry)
            }
        case .Word:
            if mode == 0 {
                data2, ovf := intrinsics.overflow_sub(i16(D[reg]), i16(data))
                carry := bool((u32(u16(D[reg])) - u32(u16(data))) >> 16)
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(u16(data2))
                cpu_prefetch()
                flags16(data2, ovf, carry)
            } else if mode == 1 {
                areg := cpu_Areg_get(reg)
                data := u32(u16(i16(areg) - i16(data)))
                areg &= 0xFFFF0000
                areg |= data
                cpu_Areg_set(reg, areg)
                cpu_prefetch()
                cpu_idle(4)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data16(mode, reg, addr) or_return
                data2, ovf := intrinsics.overflow_sub(i16(ea_data), i16(data))
                cpu_prefetch()
                cpu_write16(addr, u16(data2))
                carry := bool((u32(ea_data) - u32(u16(data))) >> 16)
                flags16(data2, ovf, carry)
            }
        case .Long:
            if mode == 0 {
                data2, ovf := intrinsics.overflow_sub(i32(D[reg]), i32(data))
                D[reg] = u32(data2)
                cpu_prefetch()
                cpu_idle(4)
                carry := bool((u64(D[reg]) - u64(u32(data))) >> 32)
                flags32(data2, ovf, carry)
            } else if mode == 1 {
                areg := cpu_Areg_get(reg)
                data := u32(i32(areg) - i32(data))
                cpu_Areg_set(reg, data)
                cpu_prefetch()
                cpu_idle(2)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data32(mode, reg, addr) or_return
                data2, ovf := intrinsics.overflow_sub(i32(ea_data), i32(data))
                cpu_prefetch()
                cpu_write32(addr, u32(data2)) or_return
                carry := bool((u64(ea_data) - u64(u32(data))) >> 32)
                flags32(data2, ovf, carry)
            }
    }
    return true
}

cpu_dbcc :: proc(opcode: u16) -> bool
{
    cond := Conditional((opcode >> 8) & 15)
    reg := (opcode >> 0) & 7
    test := cpu_cond_get(cond)

    if test == false {
        cycles -= 2
        imm := i32(i16(cpu_fetch()))
        data := u16(D[reg]) - 1
        D[reg] &= 0xFFFF0000
        D[reg] |= u32(data)
        if i16(D[reg]) != -1 {
            cpu_pc_add(imm) or_return
            cpu_refetch()
            return true
        }
    } else {
        cpu_idle(4)
        cpu_fetch()
    }
    cpu_prefetch()
    return true
}

cpu_scc :: proc(opcode: u16) -> bool
{
    cond := Conditional((opcode >> 8) & 15)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg, .Byte)
    cpu_get_ea_data8(mode, reg, addr)
    test := cpu_cond_get(cond)

    if mode == 0 {
        D[reg] &= 0xFFFFFF00
        D[reg] |= u32(u8(test) * 0xFF)
        cpu_prefetch()
        if test {
            cpu_idle(2)
        }
    } else {
        cpu_prefetch()
        cpu_write8(addr, u8(test) * 0xFF)
    }
    return true
}

cpu_bsr :: proc(opcode: u16) -> bool
{
    imm := i16(i8(opcode))
    cycles -= 2
    imm16 := i16(cpu_fetch())
    if imm == 0 {
        imm = imm16
        cpu_push32(pc + 2)
    } else {
        cpu_push32(pc)
    }

    cpu_pc_add(i32(imm)) or_return
    cpu_refetch()
    return true
}

cpu_bcc :: proc(opcode: u16) -> bool
{
    cond := Conditional((opcode >> 8) & 15)
    imm := i16(i8(opcode))
    test := cpu_cond_get(cond)

    if test == true {
        cpu_idle(2)
        if imm == 0 {
            cycles -= 4
            imm = i16(cpu_fetch())
        } else {
            pc += 2
        }
        cpu_pc_add(i32(imm)) or_return
        cpu_refetch()
        return true
    } else {
        cpu_idle(4)
        if imm == 0 {
            cpu_fetch() //Skip unused imm value
        }
    }
    cpu_prefetch()
    return true
}

cpu_moveq :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    imm := u32(i32(i8(opcode)))

    D[reg] = imm
    sr.n = bool((imm >> 31) & 1)
    sr.z = bool(imm == 0)
    sr.v = false
    sr.c = false
    cpu_prefetch()
    return true
}

cpu_divu :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg2, .Word)
    ea_data := cpu_get_ea_data16(mode, reg2, addr) or_return
    sr.c = false
    if ea_data == 0 {
        sr.z = false
        sr.v = false
        sr.n = false
        pc -= 2
        cpu_exception(.Zero)
        return false
    }

    quot := D[reg] / u32(ea_data)
    remind := D[reg] % u32(ea_data)
    ovf := quot > 0xFFFF

    if !ovf {
        hdivisor := u32(ea_data) << 16
        dividend := D[reg]
        D[reg] = u32(quot) | u32(remind << 16)
        cnt :u32= 72

        for i := 0; i < 15; i+=1
	    {
            temp := u32(dividend)
            dividend <<= 1
            if i32(temp) < 0 {
                dividend -= hdivisor
            } else {
                cnt += 4
                if dividend >= hdivisor {
                    dividend -= hdivisor
                    cnt -= 2
                }
            }
        }
        cpu_idle(cnt)
        sr.n = bool(u16(quot) >> 15)
        sr.z = quot == 0
    } else {
        cpu_idle(6)
    }
    sr.v = ovf
    cpu_prefetch()
    return true
}

cpu_divs :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7
    cnt: u32

    addr := cpu_get_address(mode, reg2, .Word)
    ea_data := cpu_get_ea_data16(mode, reg2, addr) or_return
    sr.c = false
    if ea_data == 0 {
        cpu_exception(.Zero)
        return false
    }

    cnt += 8
    dividend := D[reg]
    if i32(dividend) < 0 {
        cnt += 2
    }

    quot := i32(dividend) / i32(i16(ea_data))
    remind := i32(dividend) % i32(i16(ea_data))
    ovf := (quot > 32767) || (quot < -32767)

    if !ovf {
        D[reg] = u32(u16(quot)) | (u32(remind) << 16)
        cnt += 110
        if i16(ea_data) >= 0 {
            if i32(dividend) >= 0 {
                cnt -= 2
            } else {
                cnt += 2
            }
        }

        aquot := math.abs(i32(dividend)) / math.abs(i32(i16(ea_data)))
        for i := 0; i < 15; i += 1 {
		    if i16(aquot) >= 0 {
                cnt += 2
            }
            aquot <<= 1
	    }
        cpu_idle(cnt)
        sr.n = bool(u16(quot) >> 15)
        sr.z = quot == 0
    } else {
        cpu_idle(cnt + 4)
    }
    sr.v = ovf
    cpu_prefetch()
    return true
}

cpu_sbcd :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    rm := (opcode >> 3) & 1
    reg2 := (opcode >> 0) & 7
    data1: u8
    data2: u8
    addr: u32

    if rm == 0 {
        data1 = u8(D[reg])
        data2 = u8(D[reg2])
    } else {
        addr2 := cpu_get_address(4, reg2, .Byte)
        addr = cpu_get_address(4, reg, .Byte)
        cycles = 0
        data2 = cpu_get_ea_data8(4, reg2, addr2)
        data1 = cpu_get_ea_data8(4, reg, addr)
    }
    dd := data1 - data2 - u8(sr.x)
    bc := ((~data1 & data2) | (dd & ~data1) | (dd & data2)) & 0x88
	corf := bc - (bc >> 2)
	res := dd - corf
    sr.c = bool((bc | (~dd & res)) >> 7)
    sr.v = bool((dd & ~res) >> 7)
	if res != 0 {
        sr.z = false
    }
	sr.n = bool(res >> 7)
    sr.x = sr.c
    if rm == 0 {
        D[reg] &= 0xFFFFFF00
        D[reg] |= u32(res)
    } else {
        cpu_write8(addr, res)
    }
    cpu_idle(2)
    cpu_prefetch()
    return true
}

cpu_sub :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    dir := (opcode >> 8) & 1
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    switch size {
        case .Byte:
            addr := cpu_get_address(mode, reg2, size)
            ea_data := cpu_get_ea_data8(mode, reg2, addr)
            cpu_prefetch()
            if dir == 1 {
                data, ovf := intrinsics.overflow_sub(i8(ea_data), i8(D[reg]))
                carry := bool((u16(ea_data) - u16(u8(D[reg]))) >> 8)
                cpu_write8(addr, u8(data))
                flags8(data, ovf, carry)
            } else {
                data, ovf := intrinsics.overflow_sub(i8(D[reg]), i8(ea_data))
                carry := bool((u16(u8(D[reg])) - u16(ea_data)) >> 8)
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(u8(data))
                flags8(data, ovf, carry)
            }
        case .Word:
            addr := cpu_get_address(mode, reg2, size)
            ea_data := cpu_get_ea_data16(mode, reg2, addr) or_return
            cpu_prefetch()
            if dir == 1 {
                data, ovf := intrinsics.overflow_sub(i16(ea_data), i16(D[reg]))
                carry := bool((u32(ea_data) - u32(u16(D[reg]))) >> 16)
                cpu_write16(addr, u16(data))
                flags16(data, ovf, carry)
            } else {
                data, ovf := intrinsics.overflow_sub(i16(D[reg]), i16(ea_data))
                carry := bool((u32(u16(D[reg])) - u32(ea_data)) >> 16)
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(u16(data))
                flags16(data, ovf, carry)
            }
        case .Long:
            addr := cpu_get_address(mode, reg2, size)
            ea_data := cpu_get_ea_data32(mode, reg2, addr) or_return
            cpu_prefetch()
            if dir == 1 {
                data, ovf := intrinsics.overflow_sub(i32(ea_data), i32(D[reg]))
                carry := bool((u64(ea_data) - u64(D[reg])) >> 32)
                cpu_write32(addr, ea_data - D[reg]) or_return
                flags32(data, ovf, carry)
            } else {
                data, ovf := intrinsics.overflow_sub(i32(D[reg]), i32(ea_data))
                carry := bool((u64(D[reg]) - u64(ea_data)) >> 32)
                D[reg] = u32(data)
                if mode <= 1 || (mode == 7 && reg2 == 4) {
                    cpu_idle(4)
                } else {
                    cpu_idle(2)
                }
                flags32(data, ovf, carry)
            }
    }
    return true
}

cpu_or :: proc(opcode: u16) -> bool
{
    return cpu_alu(opcode, .Or)
}

cpu_and :: proc(opcode: u16) -> bool
{
    return cpu_alu(opcode, .And)
}

cpu_add :: proc(opcode: u16) -> bool
{
    return cpu_alu(opcode, .Add)
}

cpu_alu :: proc(opcode: u16, op: Operation) -> bool
{
    reg := (opcode >> 9) & 7
    dir := (opcode >> 8) & 1
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7
    ovf: bool

    switch size {
        case .Byte:
            data: i8
            addr := cpu_get_address(mode, reg2, size)
            ea_data := cpu_get_ea_data8(mode, reg2, addr)
            #partial switch op {
                case .Add:
                    data, ovf = intrinsics.overflow_add(i8(ea_data), i8(D[reg]))
                    carry := bool((u16(ea_data) + u16(u8(D[reg]))) >> 8)
                    flags8(data, ovf, carry)
                case .And:
                    data = i8(ea_data) & i8(D[reg])
                    flags8_2(u8(data))
                case .Or:
                    data = i8(ea_data) | i8(D[reg])
                    flags8_2(u8(data))
            }
            cpu_prefetch()
            if dir == 1 {
                cpu_write8(addr, u8(data))
            } else {
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(u8(data))
            }
        case .Word:
            data: i16
            addr := cpu_get_address(mode, reg2, size)
            ea_data := cpu_get_ea_data16(mode, reg2, addr) or_return
            #partial switch op {
                case .Add:
                    data, ovf = intrinsics.overflow_add(i16(ea_data), i16(D[reg]))
                    carry := bool((u32(ea_data) + u32(u16(D[reg]))) >> 16)
                    flags16(data, ovf, carry)
                case .And:
                    data = i16(ea_data) & i16(D[reg])
                    flags16_2(u16(data))
                case .Or:
                    data = i16(ea_data) | i16(D[reg])
                    flags16_2(u16(data))
            }
            cpu_prefetch()
            if dir == 1 {
                cpu_write16(addr, u16(data))
            } else {
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(u16(data))
            }
        case .Long:
            data: i32
            addr := cpu_get_address(mode, reg2, size)
            ea_data := cpu_get_ea_data32(mode, reg2, addr) or_return
            #partial switch op {
                case .Add:
                    data, ovf = intrinsics.overflow_add(i32(ea_data), i32(D[reg]))
                    carry := bool((u64(ea_data) + u64(u32(D[reg]))) >> 32)
                    flags32(data, ovf, carry)
                case .And:
                    data = i32(ea_data) & i32(D[reg])
                    flags32_2(u32(data))
                case .Or:
                    data = i32(ea_data) | i32(D[reg])
                    flags32_2(u32(data))
            }
            cpu_prefetch()
            if dir == 1 {
                cpu_write32(addr, u32(data)) or_return
            } else {
                D[reg] = u32(data)
                if mode <= 1 || (mode == 7 && reg2 == 4) {
                    cpu_idle(4)
                } else {
                    cpu_idle(2)
                }
            }
    }
    return true
}

cpu_addx :: proc(opcode: u16) -> bool
{
    return cpu_alux(opcode, .Add)
}

cpu_subx :: proc(opcode: u16) -> bool
{
    return cpu_alux(opcode, .Sub)
}

cpu_alux :: proc(opcode: u16, op: Operation) -> bool
{
    reg := (opcode >> 9) & 7
    size := Size((opcode >> 6) & 3)
    rm := (opcode >> 3) & 1
    reg2 := (opcode >> 0) & 7

    switch size {
        case .Byte:
            res: u8
            data1: u8
            data2: u8
            addr2: u32
            if rm == 1 {
                addr := cpu_get_address(4, reg2, size)
                data1 = cpu_get_ea_data8(4, reg2, addr)
                addr2 = cpu_get_address(4, reg, size)
                data2 = cpu_get_ea_data8(4, reg, addr2)
            } else {
                data1 = u8(D[reg2])
                data2 = u8(D[reg])
            }
            #partial switch op {
                case .Sub:
                    res = data2 - data1 - u8(sr.x)
                    sr.c = bool(((~data2 & data1) | (res & ~data2) | (res & data1)) >> 7)
                    sr.v = bool(((~data1 & data2 & ~res) | (data1 & ~data2 & res)) >> 7)
                case .Add:
                    res = data1 + data2 + u8(sr.x)
                    sr.c = bool(((data1 & data2) | (~res & data1) | (~res & data2)) >> 7)
                    sr.v = bool(((data1 & data2 & ~res) | (~data1 & ~data2 & res)) >> 7)
            }
            if rm == 1 {
                cpu_write8(addr2, u8(res))
                cycles -= 2
            } else {
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(u8(res))
            }
            if res != 0 {
                sr.z = false
            }
            sr.n = bool(res >> 7)
            sr.x = sr.c
        case .Word:
            res: u16
            data1: u16
            data2: u16
            addr2: u32
            if rm == 1 {
                addr := cpu_get_address(4, reg2, size)
                data1 = cpu_get_ea_data16(4, reg2, addr) or_return
                addr2 = cpu_get_address(4, reg, size)
                cycles -= 2
                data2 = cpu_get_ea_data16(4, reg, addr2) or_return
            } else {
                data1 = u16(D[reg2])
                data2 = u16(D[reg])
            }
            #partial switch op {
                case .Sub:
                    res = data2 - data1 - u16(sr.x)
                    sr.c = bool(((~data2 & data1) | (res & ~data2) | (res & data1)) >> 15)
                    sr.v = bool(((~data1 & data2 & ~res) | (data1 & ~data2 & res)) >> 15)
                case .Add:
                    res = data1 + data2 + u16(sr.x)
                    sr.c = bool(((data1 & data2) | (~res & data1) | (~res & data2)) >> 15)
                    sr.v = bool(((data1 & data2 & ~res) | (~data1 & ~data2 & res)) >> 15)
            }
            if rm == 1 {
                cpu_write16(addr2, u16(res))
            } else {
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(u16(res))
            }
            if res != 0 {
                sr.z = false
            }
            sr.n = bool(res >> 15)
            sr.x = sr.c
        case .Long:
            res: u32
            data1: u32
            data2: u32
            addr2: u32
            if rm == 1 {
                addr := cpu_get_address(4, reg2, size, true)
                data1 = cpu_get_ea_data32(4, reg2, addr) or_return
                addr2 = cpu_get_address(4, reg, size, true)
                cycles -= 2
                data2 = cpu_get_ea_data32(4, reg, addr2) or_return
            } else {
                data1 = D[reg2]
                data2 = D[reg]
            }
            #partial switch op {
                case .Sub:
                    res = data2 - data1 - u32(sr.x)
                    sr.c = bool(((~data2 & data1) | (res & ~data2) | (res & data1)) >> 31)
                    sr.v = bool(((~data1 & data2 & ~res) | (data1 & ~data2 & res)) >> 31)
                case .Add:
                    res = data1 + data2 + u32(sr.x)
                    sr.c = bool(((data1 & data2) | (~res & data1) | (~res & data2)) >> 31)
                    sr.v = bool(((data1 & data2 & ~res) | (~data1 & ~data2 & res)) >> 31)
            }
            if rm == 1 {
                cpu_write32(addr2, res)
            } else {
                D[reg] = res
                cycles += 4
            }
            if res != 0 {
                sr.z = false
            }
            sr.n = bool(res >> 31)
            sr.x = sr.c
    }
    cpu_prefetch()
    return true
}

cpu_suba :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    size := (opcode >> 6) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    switch size {
        case 3:
            addr := cpu_get_address(mode, reg2, .Word)
            ea_data := cpu_get_ea_data16(mode, reg2, addr) or_return
            areg := cpu_Areg_get(reg)
            data:= i32(areg) - i32(i16(ea_data))
            cpu_prefetch()
            cpu_Areg_set(reg, u32(data))
            cpu_idle(4)
        case 7:
            addr := cpu_get_address(mode, reg2, .Long)
            ea_data := cpu_get_ea_data32(mode, reg2, addr) or_return
            areg := cpu_Areg_get(reg)
            data:= i32(areg) - i32(ea_data)
            cpu_prefetch()
            cpu_Areg_set(reg, u32(data))
            if mode <= 1 || (mode == 7 && reg2 == 4) {
                cpu_idle(4)
            } else {
                cpu_idle(2)
            }
    }
    return true
}

cpu_cmpm :: proc(opcode: u16) -> bool
{
    regx := (opcode >> 9) & 7
    size := Size((opcode >> 6) & 3)
    regy := (opcode >> 0) & 7

    switch size {
        case .Byte:
            addry := cpu_get_address(3, regy, size)
            ea_datay := cpu_read8(addry)
            addrx := cpu_get_address(3, regx, size)
            ea_datax := cpu_read8(addrx)
            data, ovf := intrinsics.overflow_sub(i8(ea_datax), i8(ea_datay))
            carry := bool((u16(ea_datax) - u16(ea_datay)) >> 8)
            flags8(data, ovf, carry, false)
        case .Word:
            addry := cpu_get_address(3, regy, size)
            ea_datay := cpu_read16(addry) or_return
            addrx := cpu_get_address(3, regx, size)
            ea_datax := cpu_read16(addrx) or_return
            data, ovf := intrinsics.overflow_sub(i16(ea_datax), i16(ea_datay))
            carry := bool((u32(ea_datax) - u32(ea_datay)) >> 16)
            flags16(data, ovf, carry, false)
        case .Long:
            addry := cpu_get_address(3, regy, size)
            ea_datay := cpu_read32(addry) or_return
            addrx := cpu_get_address(3, regx, size)
            ea_datax := cpu_read32(addrx) or_return
            data, ovf := intrinsics.overflow_sub(i32(ea_datax), i32(ea_datay))
            carry := bool((u64(ea_datax) - u64(ea_datay)) >> 32)
            flags32(data, ovf, carry, false)
    }
    cpu_prefetch()
    return true
}

cpu_cmp :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    switch size {
        case .Byte:
            addr := cpu_get_address(mode, reg2, size)
            ea_data := cpu_get_ea_data8(mode, reg2, addr)
            cpu_prefetch()
            data, ovf := intrinsics.overflow_sub(i8(D[reg]), i8(ea_data))
            carry := bool((u16(u8(D[reg])) - u16(ea_data)) >> 8)
            flags8(data, ovf, carry, false)
        case .Word:
            addr := cpu_get_address(mode, reg2, size)
            ea_data := cpu_get_ea_data16(mode, reg2, addr) or_return
            cpu_prefetch()
            data, ovf := intrinsics.overflow_sub(i16(D[reg]), i16(ea_data))
            carry := bool((u32(u16(D[reg])) - u32(ea_data)) >> 16)
            flags16(data, ovf, carry, false)
        case .Long:
            addr := cpu_get_address(mode, reg2, size)
            ea_data := cpu_get_ea_data32(mode, reg2, addr) or_return
            cpu_prefetch()
            data, ovf := intrinsics.overflow_sub(i32(D[reg]), i32(ea_data))
            carry := bool((u64(D[reg]) - u64(ea_data)) >> 32)
            cpu_idle(2)
            flags32(data, ovf, carry, false)
    }
    return true
}

cpu_cmpa :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    size := (opcode >> 6) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    switch size {
        case 3:
            addr := cpu_get_address(mode, reg2, .Word)
            ea_data := i32(i16(cpu_get_ea_data16(mode, reg2, addr) or_return))
            areg := cpu_Areg_get(reg)
            data, ovf := intrinsics.overflow_sub(i32(areg), ea_data)
            carry := bool((u64(areg) - u64(u32(ea_data))) >> 32)
            cpu_prefetch()
            flags32(data, ovf, carry, false)
            cpu_idle(2)
        case 7:
            addr := cpu_get_address(mode, reg2, .Long)
            ea_data := cpu_get_ea_data32(mode, reg2, addr) or_return
            areg := cpu_Areg_get(reg)
            data, ovf := intrinsics.overflow_sub(i32(areg), i32(ea_data))
            carry := bool((u64(u32(areg)) - u64(ea_data)) >> 32)
            cpu_prefetch()
            cpu_idle(2)
            flags32(data, ovf, carry, false)
    }
    return true
}

cpu_eor :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    switch size {
        case .Byte:
            addr := cpu_get_address(mode, reg2, size)
            ea_data := cpu_get_ea_data8(mode, reg2, addr)
            data := u8(ea_data) ~ u8(D[reg])
            cpu_prefetch()

            if mode == 0 {
                D[reg2] &= 0xFFFFFF00
                D[reg2] |= u32(data)
            } else {
                cpu_write8(addr, data)
            }
            flags8_2(data)
        case .Word:
            addr := cpu_get_address(mode, reg2, size)
            ea_data := cpu_get_ea_data16(mode, reg2, addr) or_return
            data := u16(D[reg]) ~ u16(ea_data)
            cpu_prefetch()

            if mode == 0 {
                D[reg2] &= 0xFFFF0000
                D[reg2] |= u32(data)
            } else {
                cpu_write16(addr, data)
            }
            flags16_2(data)
        case .Long:
            addr := cpu_get_address(mode, reg2, size)
            ea_data := cpu_get_ea_data32(mode, reg2, addr) or_return
            data := D[reg] ~ ea_data
            cpu_prefetch()
            if mode == 0 {
                D[reg2] = u32(data)
                cpu_idle(4)
            } else {
                cpu_write32(addr, data) or_return
            }
            flags32_2(data)
    }
    return true
}

cpu_mulu :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg2, .Word)
    ea_data := cpu_get_ea_data16(mode, reg2, addr) or_return
    data, ovf := intrinsics.overflow_mul(u32(ea_data), u32(u16(D[reg])))
    D[reg] = data

    sr.c = false
    sr.v = ovf
    sr.z = data == 0
    sr.n = bool(data >> 31)
    cpu_prefetch()
    cpu_idle(34 + u32(intrinsics.count_ones(ea_data) * 2))
    return true
}

cpu_muls :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg2, .Word)
    ea_data := cpu_get_ea_data16(mode, reg2, addr) or_return
    data, ovf := intrinsics.overflow_mul(i32(i16(ea_data)), i32(i16(D[reg])))
    D[reg] = u32(data)

    src17 := u32(ea_data) << 1
    n :u32= 0
    for i in u32(0)..=15 {
        first := (1 << (i + 1)) & src17 > 0
        second := (1 << i) & src17 > 0
        if first != second do n += 1
    }

    sr.c = false
    sr.v = ovf
    sr.z = data == 0
    sr.n = bool(data >> 31)
    cpu_prefetch()
    cpu_idle(34 + (n * 2))
    return true
}

cpu_abcd :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    rm := (opcode >> 3) & 1
    reg2 := (opcode >> 0) & 7
    data1: u8
    data2: u8
    addr: u32

    if rm == 0 {
        data1 = u8(D[reg])
        data2 = u8(D[reg2])
    } else {
        addr2 := cpu_get_address(4, reg2, .Byte)
        addr = cpu_get_address(4, reg, .Byte)
        cycles = 0
        cpu_idle(2)
        data2 = cpu_get_ea_data8(4, reg2, addr2)
        data1 = cpu_get_ea_data8(4, reg, addr)
    }
    ss := data1 + data2 + u8(sr.x)
    bc := ((data1 & data2) | (~ss & data1) | (~ss & data2)) & 0x88
    dc := u8((((u16(ss) + 0x66) ~ u16(ss)) & 0x110) >> 1)
	corf := (bc | dc) - ((bc | dc) >> 2)
	res := ss + corf
    sr.c = bool((bc | (ss & ~res)) >> 7)
    sr.v = bool((~ss & res) >> 7)
	if res != 0 {
        sr.z = false
    }
	sr.n = bool(res >> 7)
    sr.x = sr.c

    cpu_prefetch()
    if rm == 0 {
        D[reg] &= 0xFFFFFF00
        D[reg] |= u32(res)
        cpu_idle(2)
    } else {
        cpu_write8(addr, res)
    }
    return true
}

cpu_exg :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    mode := (opcode >> 3) & 0x1F
    reg2 := (opcode >> 0) & 7

    switch mode {
        case 0x08:  //D D
            tmp_reg := D[reg]
            D[reg] = D[reg2]
            D[reg2] = tmp_reg
        case 0x09:  //A A
            tmp_reg := cpu_Areg_get(reg)
            cpu_Areg_set(reg, cpu_Areg_get(reg2))
            cpu_Areg_set(reg2, tmp_reg)
        case 0x11:  //D A
            tmp_reg := D[reg]
            D[reg] = cpu_Areg_get(reg2)
            cpu_Areg_set(reg2, tmp_reg)
    }
    cpu_prefetch()
    cpu_idle(2)
    return true
}

cpu_adda :: proc(opcode: u16) -> bool
{
    reg := (opcode >> 9) & 7
    size := (opcode >> 6) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    switch size {
        case 3:
            addr := cpu_get_address(mode, reg2, .Word)
            ea_data := cpu_get_ea_data16(mode, reg2, addr) or_return
            areg := cpu_Areg_get(reg)
            data:= i32(i16(ea_data)) + i32(areg)
            cpu_prefetch()
            cpu_Areg_set(reg, u32(data))
            cpu_idle(4)
        case 7:
            addr := cpu_get_address(mode, reg2, .Long)
            ea_data := cpu_get_ea_data32(mode, reg2, addr) or_return
            areg := cpu_Areg_get(reg)
            data:= i32(ea_data) + i32(areg)
            cpu_prefetch()
            cpu_Areg_set(reg, u32(data))
            if mode <= 1 || (mode == 7 && reg2 == 4) {
                cpu_idle(4)
            } else {
                cpu_idle(2)
            }
    }
    return true
}

cpu_asd_mem :: proc(opcode: u16) -> bool
{
    dir := (opcode >> 8) & 1
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    data: u16
    last: bool
    first: bool

    addr := cpu_get_address(mode, reg, .Word)
    ea_data := cpu_get_ea_data16(mode, reg, addr) or_return

    if dir == 1 {
        data = ea_data << 1
        last = bool(ea_data >> 15)
        first = last
    } else {
        last = bool(ea_data >> 15)
        first = bool(ea_data & 1)
        data = ea_data >> 1
        if last {
            data |= 0x8000
        }
    }
    cpu_prefetch()
    cpu_write16(addr, data)

    sr.n = bool(data >> 15)
    sr.v = sr.n ~ last
    sr.z = data == 0
    sr.x = first
    sr.c = sr.x
    return true
}

cpu_lsd_mem :: proc(opcode: u16) -> bool
{
    dir := (opcode >> 8) & 1
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    data: u16
    last: bool

    addr := cpu_get_address(mode, reg, .Word)
    ea_data := cpu_get_ea_data16(mode, reg, addr) or_return

    if dir == 1 {
        data = ea_data << 1
        last = bool(ea_data >> 15)
    } else {
        last = bool(ea_data & 1)
        data = ea_data >> 1
    }
    cpu_prefetch()
    cpu_write16(addr, data)

    sr.n = bool(data >> 15)
    sr.v = false
    sr.z = data == 0
    sr.x = last
    sr.c = sr.x
    return true
}

cpu_roxd_mem :: proc(opcode: u16) -> bool
{
    dir := (opcode >> 8) & 1
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    data: u16
    last: bool

    addr := cpu_get_address(mode, reg, .Word)
    ea_data := cpu_get_ea_data16(mode, reg, addr) or_return

    if dir == 1 {
        last = bool(ea_data >> 15)
        data = (ea_data << 1) | u16(sr.x)
    } else {
        last = bool(ea_data & 1)
        data = (ea_data >> 1) | (u16(sr.x) << 15)
    }
    cpu_prefetch()
    cpu_write16(addr, data)

    sr.n = bool(data >> 15)
    sr.v = false
    sr.z = data == 0
    sr.x = last
    sr.c = sr.x
    return true
}

cpu_rod_mem :: proc(opcode: u16) -> bool
{
    dir := (opcode >> 8) & 1
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    data: u16
    last: bool

    addr := cpu_get_address(mode, reg, .Word)
    ea_data := cpu_get_ea_data16(mode, reg, addr) or_return

    if dir == 1 {
        last = bool(ea_data >> 15)
        data = (ea_data << 1) | (ea_data >> 15)
    } else {
        last = bool(ea_data & 1)
        data = (ea_data >> 1) | (ea_data << 15)
    }
    cpu_prefetch()
    cpu_write16(addr, data)

    sr.n = bool(data >> 15)
    sr.v = false
    sr.z = data == 0
    sr.c = last
    return true
}

cpu_asd_reg :: proc(opcode: u16) -> bool
{
    reg_cnt := (opcode >> 9) & 7
    dir := (opcode >> 8) & 1
    size := Size((opcode >> 6) & 3)
    ir := (opcode >> 5) & 1
    reg := (opcode >> 0) & 7
    cnt: u8
    last: bool

    if ir == 1 {
        cnt = u8(D[reg_cnt]%64)
    } else {
        cnt = u8(reg_cnt)
        if reg_cnt == 0 {
            cnt = 8
        } else {
            cnt = u8(reg_cnt)
        }
    }
    sr.v = false
    cpu_prefetch()
    switch size {
        case .Byte:
            data: u8
            cnt2 := cnt
            if cnt2 > 8 {
                cnt2 = 8
            }
            if dir == 1 {
                first := bool((D[reg] >> 7) & 1)
                src9 := u16(D[reg]) << 1
                for i in u32(8 - cnt2)..=7 {
                    second := (1 << i) & src9 > 0
                    if first != second {
                        sr.v = true
                        break
                    }
                }

                last = bool((D[reg] >> (8 - cnt)) & 1)
                data = u8(D[reg]) << cnt
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(data)
            } else {
                last = bool((u8(D[reg]) >> (cnt - 1)) & 1)
                data = u8(D[reg]) >> cnt
                if D[reg] & 0x80 == 0x80 {
                    msbs: u8
                    for i in 0..<u32(cnt2) {
                        msbs |= (1 << i)
                    }
                    msbs <<= 8 - cnt2
                    data |= msbs
                }
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(data)
                sr.v = false
            }
            sr.z = data == 0
            sr.n = bool(data >> 7)
            cpu_idle(2 + 2 * u32(cnt))
        case .Word:
            data: u16
            cnt2 := cnt
            if cnt2 > 16 {
                cnt2 = 16
            }
            if dir == 1 {
                first := bool((D[reg] >> 15) & 1)
                src17 := u32(D[reg]) << 1
                for i in u32(16 - cnt2)..=15 {
                    second := (1 << i) & src17 > 0
                    if first != second {
                        sr.v = true
                        break
                    }
                }

                last = bool((D[reg] >> (16 - cnt)) & 1)
                data = u16(D[reg]) << cnt
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(data)
            } else {
                last = bool((u16(D[reg]) >> (cnt - 1)) & 1)
                data = u16(D[reg]) >> cnt
                if D[reg] & 0x8000 == 0x8000 {
                    msbs: u16
                    for i in 0..<u32(cnt2) {
                        msbs |= (1 << i)
                    }
                    msbs <<= 16 - cnt2
                    data |= msbs
                }
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(data)
                sr.v = false
            }
            sr.z = data == 0
            sr.n = bool(data >> 15)
            cpu_idle(2 + 2 * u32(cnt))
        case .Long:
            data: u32
            cnt2 := cnt
            if cnt2 > 32 {
                cnt2 = 32
            }
            if dir == 1 {
                first := bool((D[reg] >> 31) & 1)
                src33 := u64(D[reg]) << 1
                for i in u64(32 - cnt2)..=31 {
                    second := (1 << i) & src33 > 0
                    if first != second {
                        sr.v = true
                        break
                    }
                }

                last = bool((D[reg] >> (32 - cnt)) & 1)
                data = u32(D[reg]) << cnt
                D[reg] = data
            } else {
                last = bool((D[reg] >> (cnt - 1)) & 1)
                data = D[reg] >> cnt
                if D[reg] & 0x80000000 == 0x80000000 {
                    msbs: u32
                    for i in 0..<u32(cnt2) {
                        msbs |= (1 << i)
                    }
                    msbs <<= 32 - cnt2
                    data |= msbs
                }
                D[reg] = data
                sr.v = false
            }
            sr.z = data == 0
            sr.n = bool(data >> 31)
            cpu_idle(4 + 2 * u32(cnt))
    }
    if cnt == 0 {
        sr.c = false
    } else {
        sr.x = last
        sr.c = sr.x
    }
    return true
}

cpu_lsd_reg :: proc(opcode: u16) -> bool
{
    reg_cnt := (opcode >> 9) & 7
    dir := (opcode >> 8) & 1
    size := Size((opcode >> 6) & 3)
    ir := (opcode >> 5) & 1
    reg := (opcode >> 0) & 7
    cnt: u8
    last: bool

    if ir == 1 {
        cnt = u8(D[reg_cnt]%64)
    } else {
        cnt = u8(reg_cnt)
        if reg_cnt == 0 {
            cnt = 8
        } else {
            cnt = u8(reg_cnt)
        }
    }
    cpu_prefetch()
    switch size {
        case .Byte:
            data: u8
            if dir == 1 {
                last = bool((D[reg] >> (8 - cnt)) & 1)
                data = u8(D[reg]) << cnt
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(data)
            } else {
                last = bool((u8(D[reg]) >> (cnt - 1)) & 1)
                data = u8(D[reg]) >> cnt
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(data)
            }
            sr.z = data == 0
            sr.n = bool(data >> 7)
            cpu_idle(2 + 2 * u32(cnt))
        case .Word:
            data: u16
            if dir == 1 {
                last = bool((D[reg] >> (16 - cnt)) & 1)
                data = u16(D[reg]) << cnt
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(data)
            } else {
                last = bool((u16(D[reg]) >> (cnt - 1)) & 1)
                data = u16(D[reg]) >> cnt
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(data)
            }
            sr.z = data == 0
            sr.n = bool(data >> 15)
            cpu_idle(2 + 2 * u32(cnt))
        case .Long:
            data: u32
            if dir == 1 {
                last = bool((D[reg] >> (32 - cnt)) & 1)
                data = u32(D[reg]) << cnt
                D[reg] = data
            } else {
                last = bool((D[reg] >> (cnt - 1)) & 1)
                data = D[reg] >> cnt
                D[reg] = data
            }
            sr.z = data == 0
            sr.n = bool(data >> 31)
            cpu_idle(4 + 2 * u32(cnt))
    }
    if cnt == 0 {
        sr.c = false
    } else {
        sr.x = last
        sr.c = sr.x
    }
    sr.v = false
    return true
}

cpu_roxd_reg :: proc(opcode: u16) -> bool
{
    reg_cnt := (opcode >> 9) & 7
    dir := (opcode >> 8) & 1
    size := Size((opcode >> 6) & 3)
    ir := (opcode >> 5) & 1
    reg := (opcode >> 0) & 7
    cnt: u8
    last: bool

    if ir == 1 {
        cnt = u8(D[reg_cnt]%64)
    } else {
        cnt = u8(reg_cnt)
        if reg_cnt == 0 {
            cnt = 8
        } else {
            cnt = u8(reg_cnt)
        }
    }
    cpu_prefetch()
    switch size {
        case .Byte:
            data: u8
            cnt2 := cnt % 9
            if dir == 1 {
                last = bool((D[reg] >> (8 - cnt2)) & 1)
                data = u8(D[reg]) << cnt2
                rot := u8(D[reg]) >> (8 - cnt2 + 1)
                x := u8(sr.x) << (cnt2 - 1)
                D[reg] &= 0xFFFFFF00
                data = data | rot | x
                D[reg] |= u32(data)
            } else {
                last = bool((u8(D[reg]) >> (cnt2 - 1)) & 1)
                data = u8(D[reg]) >> cnt2
                rot := u8(D[reg]) << (9 - cnt2)
                x := u8(sr.x) << (8 - cnt2)
                D[reg] &= 0xFFFFFF00
                data = data | rot | x
                D[reg] |= u32(data)
            }
            sr.z = data == 0
            sr.n = bool(data >> 7)
            if (cnt2) != 0 {
                sr.x = last
            }
            sr.c = sr.x
            cpu_idle(2 + 2 * u32(cnt))
        case .Word:
            data: u16
            cnt2 := cnt % 17
            if dir == 1 {
                last = bool((D[reg] >> (16 - cnt2)) & 1)
                data = u16(D[reg]) << cnt2
                rot := u16(D[reg]) >> (16 - cnt2 + 1)
                x := u16(sr.x) << (cnt2 - 1)
                D[reg] &= 0xFFFF0000
                data = data | rot | x
                D[reg] |= u32(data)
            } else {
                last = bool((u16(D[reg]) >> (cnt2 - 1)) & 1)
                data = u16(D[reg]) >> cnt2
                rot := u16(D[reg]) << (17 - cnt2)
                x := u16(sr.x) << (16 - cnt2)
                D[reg] &= 0xFFFF0000
                data = data | rot | x
                D[reg] |= u32(data)
            }
            sr.z = data == 0
            sr.n = bool(data >> 15)
            if (cnt2) != 0 {
                sr.x = last
            }
            sr.c = sr.x
            cpu_idle(2 + 2 * u32(cnt))
        case .Long:
            data: u32
            cnt2 := cnt % 33
            if dir == 1 {
                last = bool((D[reg] >> (32 - cnt2)) & 1)
                data = D[reg] << cnt2
                rot := D[reg] >> (32 - cnt2 + 1)
                x := u32(sr.x) << (cnt2 - 1)
                data = data | rot | x
                D[reg] = data
            } else {
                last = bool((D[reg] >> (cnt2 - 1)) & 1)
                data = D[reg] >> cnt2
                rot := D[reg] << (33 - cnt2)
                x := u32(sr.x) << (32 - cnt2)
                data = data | rot | x
                D[reg] = data
            }
            sr.z = data == 0
            sr.n = bool(data >> 31)
            if (cnt2) != 0 {
                sr.x = last
            }
            sr.c = sr.x
            cpu_idle(4 + 2 * u32(cnt))
    }
    sr.v = false
    return true
}

cpu_rod_reg :: proc(opcode: u16) -> bool
{
    reg_cnt := (opcode >> 9) & 7
    dir := (opcode >> 8) & 1
    size := Size((opcode >> 6) & 3)
    ir := (opcode >> 5) & 1
    reg := (opcode >> 0) & 7
    cnt: u8
    last: bool

    if ir == 1 {
        cnt = u8(D[reg_cnt]%64)
    } else {
        cnt = u8(reg_cnt)
        if reg_cnt == 0 {
            cnt = 8
        } else {
            cnt = u8(reg_cnt)
        }
    }
    cpu_prefetch()
    switch size {
        case .Byte:
            data: u8
            cnt2 := cnt % 8
            if dir == 1 {
                last = bool((D[reg] >> (8 - cnt2)) & 1)
                if cnt2 == 0 {
                    last = bool(D[reg] & 1)
                }
                data = u8(D[reg]) << cnt2
                rot := u8(D[reg]) >> (8 - cnt2)
                D[reg] &= 0xFFFFFF00
                data = data | rot
                D[reg] |= u32(data)
            } else {
                last = bool((u8(D[reg]) >> (cnt2 - 1)) & 1)
                if cnt2 == 0 {
                    last = bool((D[reg] >> 7) & 1)
                }
                data = u8(D[reg]) >> cnt2
                rot := u8(D[reg]) << (8 - cnt2)
                D[reg] &= 0xFFFFFF00
                data = data | rot
                D[reg] |= u32(data)
            }
            sr.z = data == 0
            sr.n = bool(data >> 7)
            if (cnt) == 0 {
                sr.c = false
            } else {
                sr.c = last
            }
            cpu_idle(2 + 2 * u32(cnt))
        case .Word:
            data: u16
            cnt2 := cnt % 16
            if dir == 1 {
                last = bool((D[reg] >> (16 - cnt2)) & 1)
                if cnt2 == 0 {
                    last = bool(D[reg] & 1)
                }
                data = u16(D[reg]) << cnt2
                rot := u16(D[reg]) >> (16 - cnt2)
                D[reg] &= 0xFFFF0000
                data = data | rot
                D[reg] |= u32(data)
            } else {
                last = bool((u16(D[reg]) >> (cnt2 - 1)) & 1)
                if cnt2 == 0 {
                    last = bool((D[reg] >> 15) & 1)
                }
                data = u16(D[reg]) >> cnt2
                rot := u16(D[reg]) << (16 - cnt2)
                D[reg] &= 0xFFFF0000
                data = data | rot
                D[reg] |= u32(data)
            }
            sr.z = data == 0
            sr.n = bool(data >> 15)
            if (cnt) == 0 {
                sr.c = false
            } else {
                sr.c = last
            }
            cpu_idle(2 + 2 * u32(cnt))
        case .Long:
            data: u32
            cnt2 := cnt % 32
            if dir == 1 {
                last = bool((D[reg] >> (32 - cnt2)) & 1)
                if cnt2 == 0 {
                    last = bool(D[reg] & 1)
                }
                data = D[reg] << cnt2
                rot := D[reg] >> (32 - cnt2)
                data = data | rot
                D[reg] = data
            } else {
                last = bool((D[reg] >> (cnt2 - 1)) & 1)
                if cnt2 == 0 {
                    last = bool((D[reg] >> 31) & 1)
                }
                data = D[reg] >> cnt2
                rot := D[reg] << (32 - cnt2)
                data = data | rot
                D[reg] = data
            }
            sr.z = data == 0
            sr.n = bool(data >> 31)
            if (cnt) == 0 {
                sr.c = false
            } else {
                sr.c = last
            }
            cycles += 4 + 2 * u32(cnt)
    }
    sr.v = false
    return true
}

cpu_line1010 :: proc(opcode: u16) -> bool
{
    cpu_exception(.Line1010)
    return true
}

cpu_line1111 :: proc(opcode: u16) -> bool
{
    cpu_exception(.Line1111)
    return true
}

@(private="file")
flags8 :: proc(data: i8, ovf: bool, carry: bool, ext:= true)
{
    sr.c = carry            //Carry
    sr.v = ovf              //Overflow
    sr.z = data == 0        //Zero
    sr.n = bool(data >> 7)  //Negative
    if ext {
        sr.x = sr.c         //Extend
    }
}

@(private="file")
flags16 :: proc(data: i16, ovf: bool, carry: bool, ext:= true)
{
    sr.c = carry            //Carry
    sr.v = ovf              //Overflow
    sr.z = data == 0        //Zero
    sr.n = bool(data >> 15) //Negative
    if ext {
        sr.x = sr.c         //Extend
    }
}

@(private="file")
flags32 :: proc(data: i32, ovf: bool, carry: bool, ext:= true)
{
    sr.c = carry            //Carry
    sr.v = ovf              //Overflow
    sr.z = data == 0        //Zero
    sr.n = bool(data >> 31) //Negative
    if ext {
        sr.x = sr.c         //Extend
    }
}

@(private="file")
flags8_2 :: proc(data: u8)
{
    sr.c = false            //Carry
    sr.v = false            //Overflow
    sr.z = data == 0        //Zero
    sr.n = bool(data >> 7)  //Negative
}

@(private="file")
flags16_2 :: proc(data: u16)
{
    sr.c = false            //Carry
    sr.v = false            //Overflow
    sr.z = data == 0        //Zero
    sr.n = bool(data >> 15) //Negative
}

@(private="file")
flags32_2 :: proc(data: u32)
{
    sr.c = false            //Carry
    sr.v = false            //Overflow
    sr.z = data == 0        //Zero
    sr.n = bool(data >> 31) //Negative
}

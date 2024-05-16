package main

import "core:fmt"
import "core:math"
import "base:intrinsics"

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
    And,
    Or,
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
@(private="file")
stop: bool

cpu_init :: proc()
{
    fmt.println("Cpu init") //Get rid of unused fmt error
    //pc = 0x400000
    cpu_exception_reset()
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
    if stop {
        return 0
    }
    cpu_decode(prefetch[0])
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
cpu_get_address :: proc(mode: u16, reg: u16, size: Size) -> u32
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
                    index_reg: u64
                    if da == 1 {
                        index_reg = u64(cpu_Areg_get(ireg))
                    } else {
                        index_reg = u64(D[ireg])
                    }
                    if wl == 0 {
                        index_reg = u64(i16(index_reg))
                    }
                    cycles += 2
                    addr = u32(i64(i8(ext1)) + i64(pc) + i64(index_reg))
            }
    }
    return addr
}

@(private="file")
cpu_get_cycles_lea_pea :: proc(mode: u16, reg: u16)
{
    switch mode {
        case 2:
            cycles += 12
        case 5:
            cycles += 16
        case 6:
            cycles += 20
        case 7:
            switch reg {
                case 0, 2:
                    cycles += 16
                case 1, 3:
                    cycles += 20
            }
    }
}

@(private="file")
cpu_get_cycles_jmp_jsr :: proc(mode: u16, reg: u16)
{
    switch mode {
        case 2:
            cycles += 16
        case 5:
            cycles += 18
        case 6:
            cycles += 22
        case 7:
            switch reg {
                case 0, 2:
                    cycles += 18
                case 1:
                    cycles += 20
                case 3:
                    cycles += 22
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
    } else if mode == 1 {
        data = u16(cpu_Areg_get(reg))
    } else if mode == 7 && reg == 4 {
        data = cpu_fetch()
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
    } else if mode == 1 {
        data = cpu_Areg_get(reg)
    } else if mode == 7 && reg == 4 {
        data = u32(cpu_fetch()) << 16
        data |= u32(cpu_fetch())
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
    sr.intr_mask = 7    //TODO; Check this
    ssp = bus_read32(0x00)
    pc = bus_read32(0x04)
    cpu_refetch()
    stop = false
}

@(private="file")
cpu_exception :: proc(exc: Exception, opcode: u16)
{
    exc_vec: u32
    tmp_sr := u16(sr)
    sr.super = true
    sr.trace = 0
    sr.intr_mask = 7    //TODO; Check this

    ssp -= 4
    bus_write32(ssp, pc)
    ssp -= 2
    bus_write16(ssp, tmp_sr)
    #partial switch exc {
        case .Illegal:
            exc_vec = 16
            cycles += 34
        case .Zero:
            exc_vec = 20
            cycles += 38
        case .CHK:
            exc_vec = 24
            cycles += 40
        case .TrapV:
            exc_vec = 28
            cycles += 34
        case .Trap:
            exc_vec = 128 + (u32(opcode & 0xF) << 2)
            cycles += 34
        case .Privilege:
            exc_vec = 32
            cycles += 34
        case .Trace:
            exc_vec = 36
            cycles += 34
            stop = false
        case .Uninitialized:
            exc_vec = 60
            cycles += 44 //?
        case .Spurious:
            exc_vec = 96
            cycles += 44 //?
        case .Interrupt:
            cycles += 44
            stop = false
    }
    pc = bus_read32(exc_vec)
    cpu_refetch()
}

// TODO: Still needs loads of work
@(private="file")
cpu_exception_addr :: proc(exc: Exception, addr: u32, opcode: u16)
{
    exc_vec: u32
    function_code :u16= 5
    r_w := true
    i_n := false
    tmp_sr := u16(sr)
    sr.super = true
    sr.trace = 0
    sr.intr_mask = 7    //TODO; Check this

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
    }
    ssp -= 2
    bus_write16(ssp, opcode)
    ssp -= 4
    bus_write32(ssp, addr)
    ssp -= 2
    flags:u16= ((opcode & 0xFFE0))
    flags |= u16(r_w) << 4
    flags |= u16(i_n) << 3
    flags |= function_code
    bus_write16(ssp, flags)
    pc = bus_read32(exc_vec)
    cpu_refetch()
}

cpu_decode :: proc(opcode: u16) -> u32
{
    cycles = 0
    first := (opcode >> 12)
    switch first {
        case 0x0:
            cpu_decode_0(opcode)
        case 0x1..=0x3:
            if (opcode >> 6)& 3 == 1 {  //MOVEA
                //cpu_movea(opcode)
            } else {                    //MOVE
                //cpu_move(opcode)
            }
        case 0x4:
            cpu_decode_4(opcode)
        case 0x5:
            cpu_decode_5(opcode)
        case 0x6:
            cpu_decode_6(opcode)
        case 0x7:                       //MOVEQ
            //cpu_moveq(opcode)
        case 0x8:
            cpu_decode_8(opcode)
        case 0x9:
            cpu_decode_9(opcode)
        case 0xB:
            cpu_decode_B(opcode)
        case 0xC:
            cpu_decode_C(opcode)
        case 0xD:
            cpu_decode_D(opcode)
        case 0xE:
            cpu_decode_E(opcode)
    }
    if cycles == 0 {
        cpu_exception(.Illegal, opcode)
    }
    return cycles
}

@(private="file")
cpu_decode_0 :: proc(opcode: u16)
{
    second := (opcode >> 8) & 0xF
    switch second {
        case 0x0:
            sub_code := opcode & 0xFF
            switch sub_code {
                case 0x3C:      //ORI CCR
                    cpu_ori_ccr(opcode)
                case 0x7C:      //ORI SR
                    cpu_ori_sr(opcode)
                case:           //ORI
                    cpu_ori(opcode)
            }
        case 0x2:
            sub_code := opcode & 0xFF
            switch sub_code {
                case 0x3C:      //ANDI CCR
                    cpu_andi_ccr(opcode)
                case 0x7C:      //ANDI SR
                    cpu_andi_sr(opcode)
                case:           //ANDI
                    cpu_andi(opcode)
            }
        case 0x4:               //SUBI
            cpu_subi(opcode)
        case 0x6:               //ADDI
            cpu_addi(opcode)
        case 0x8:
            sub_code := (opcode >> 6) & 3
            switch sub_code {
                case 0x0:       //BTST
                    //cpu_btst(opcode)
                case 0x1:       //BCHG
                    //cpu_bchg(opcode)
                case 0x2:       //BCLR
                    //cpu_bclr(opcode)
                case 0x3:       //BSET
                    //cpu_bset(opcode)
            }
        case 0xA:
            sub_code := opcode & 0xFF
            switch sub_code {
                case 0x3C:      //EORI CCR
                    cpu_eori_ccr(opcode)
                case 0x7C:      //EORI SR
                    cpu_eori_sr(opcode)
                case:           //EORI
                    cpu_eori(opcode)
            }
        case 0xC:               //CMPI
            cpu_cmpi(opcode)
        case:
            sub_code := (opcode >> 6) & 3
            switch sub_code {
                case 0x0:       //BTST
                    //cpu_btst(opcode)
                case 0x1:       //BCHG
                    //cpu_bchg(opcode)
                case 0x2:       //BCLR
                    //cpu_bclr(opcode)
                case 0x3:       //BSET
                    //cpu_bset(opcode)
            }
    }
}

@(private="file")
cpu_decode_4 :: proc(opcode: u16)
{
    second := (opcode >> 8) & 0xF
    switch second {
        case 0x0:
            if (opcode >> 6) & 3 == 3 { //MOVE from SR
                cpu_move_from_sr(opcode)
            } else {                    //NEGX

            }
        case 0x2:                       //CLR
            cpu_clr(opcode)
        case 0x4:
            if (opcode >> 6) & 3 == 3 { //MOVE to CCR
                cpu_move_ccr(opcode)
            } else {                    //NEG
                cpu_neg(opcode)
            }
        case 0x6:
            if (opcode >> 6) & 3 == 3 { //MOVE to SR
                cpu_move_to_sr(opcode)
            } else {                    //NOT
                cpu_not(opcode)
            }
        case 0x8:
            if (opcode & 0xFFB8) == 0x4880 {        //EXT
                cpu_ext(opcode)
            } else if (opcode >> 3) & 0x3F == 8 {   //SWAP
                cpu_swap(opcode)
            } else if (opcode >> 6) & 3 == 1 {      //PEA
                cpu_pea(opcode)
            } else {                                //NPCD

            }
        case 0xA:
            if (opcode >> 6) & 3 == 3 {
                if (opcode & 0x3F) == 0x3C {        //ILLEGAL
                    cpu_illegal(opcode)
                } else {                //TAS
                    cpu_tas(opcode)
                }
            } else {                    //TST
                cpu_tst(opcode)
            }
        case 0xC:                       //MOVEM

        case 0xE:
            sub_code := (opcode >> 4) & 0xF
            switch sub_code {
                case 0x4:               //TRAP
                    cpu_trap(opcode)
                case 0x5:               //Link/UNLK
                    if (opcode >> 3) & 1 == 0 {
                        cpu_link(opcode)
                    } else {
                        cpu_unlk(opcode)
                    }
                case 0x6:               //MOVE USP
                    cpu_move_usp(opcode)
                case 0x7:
                    switch (opcode & 0xF) {
                        case 0x0:       //RESET
                            cpu_reset(opcode)
                        case 0x1:       //NOP
                            cpu_nop(opcode)
                        case 0x2:       //STOP
                            cpu_stop(opcode)
                        case 0x3:       //RTE

                        case 0x5:       //RTS

                        case 0x6:       //TRAPV
                            cpu_trapv(opcode)
                        case 0x7:       //RTR
                    }
                case:
                    switch (opcode >> 6) & 7 {
                        case 2:         //JSR
                            //cpu_jsr(opcode)
                        case 3:         //JMP
                            //cpu_jmp(opcode)
                    }
            }
        case:
            switch (opcode >> 6) & 7 {
                case 6:         //CHK

                case 7:         //LEA
                    cpu_lea(opcode)
            }
    }
}

@(private="file")
cpu_decode_5 :: proc(opcode: u16)
{
    if (opcode >> 6) & 3 == 3 { //Scc/DBcc

    } else {
        if (opcode >> 8) & 1 == 0 {
            cpu_addq(opcode)    //ADDQ
        } else {
            cpu_subq(opcode)    //SUBQ
        }
    }
}

@(private="file")
cpu_decode_6 :: proc(opcode: u16)
{
    second := (opcode >> 8) & 0xF
    switch second {
        case 0x0:
            //cpu_bra(opcode)
        case 0x1:
            //cpu_bsr(opcode)
        case:
            //cpu_bcc(opcode)
    }
}

@(private="file")
cpu_decode_8 :: proc(opcode: u16)
{
    sub_code := (opcode >> 6) & 7
    switch sub_code {
        case 3:         //DIVU
            cpu_divu(opcode)
        case 7:         //DIVS
            cpu_divs(opcode)
        case:
            if (opcode >> 4) & 31 == 16 {//SBCD
                fmt.println("BLA")
            } else {    //OR
                cpu_alu(opcode, .Or)
            }

    }
}

@(private="file")
cpu_decode_9 :: proc(opcode: u16)
{
    if (opcode >> 6) & 3 == 3 { //SUBA
        cpu_suba(opcode)
    } else if (opcode & 0xF130) == 0x9100 {//SUBX

    } else {                    //SUB
        cpu_sub(opcode)
    }
}

@(private="file")
cpu_decode_B :: proc(opcode: u16)
{
    if (opcode >> 6) & 3 == 3 {         //CMPA
        cpu_cmpa(opcode)
    } else if (opcode & 0x100 == 0) {   //CMP
        cpu_cmp(opcode)
    } else if (opcode & 0x138) == 0x108 {//CMPM
        cpu_cmpm(opcode)
    } else {
        cpu_eor(opcode)                 //EOR
    }
}

@(private="file")
cpu_decode_C :: proc(opcode: u16)
{
    sub_code := (opcode >> 4) & 0x1F
    switch sub_code {
        case 0x0C..=0x0F://MULU
            cpu_mulu(opcode)
        case 0x1C..=0x1F://MULS
            cpu_muls(opcode)
        case 0x10:      //ABCD

        case 0x14, 0x18://EXG
            cpu_exg(opcode)
        case:           //AND
            cpu_alu(opcode, .And)
    }
}

@(private="file")
cpu_decode_D :: proc(opcode: u16)
{
    if (opcode >> 6) & 3 == 3 { //ADDA
        cpu_adda(opcode)
    } else if (opcode & 0xF130) == 0x9100 {//ADDX

    } else {                    //ADD
        cpu_alu(opcode, .Add)
    }
}

@(private="file")
cpu_decode_E :: proc(opcode: u16)
{
    if (opcode >> 6) & 3 == 3 {
        sub_code := (opcode >> 9) & 7
        switch sub_code {
            case 0:
                cpu_asd_mem(opcode)
            case 1:
                cpu_lsd_mem(opcode)
            case 2:
                cpu_roxd_mem(opcode)
            case 3:
                cpu_rod_mem(opcode)
        }
    } else {
        sub_code := (opcode >> 3) & 3
        switch sub_code {
            case 0:
                cpu_asd_reg(opcode)
            case 1:
                cpu_lsd_reg(opcode)
            case 2:
                cpu_roxd_reg(opcode)
            case 3:
                cpu_rod_reg(opcode)
        }
    }
}

@(private="file")
cpu_ori_ccr :: proc(opcode: u16)
{
    imm := u8(cpu_fetch() & 0xFF)
    tmp_sr := u16(sr)
    ccr := u8(tmp_sr) | imm
    tmp_sr &= 0xFF00
    sr = SR(tmp_sr | u16(ccr & 0x1F))
    cycles += 16
    cpu_prefetch()
}

@(private="file")
cpu_ori_sr :: proc(opcode: u16)
{
    if sr.super {
        imm := cpu_fetch()
        tmp_sr := u16(sr) | imm
        tmp_sr &= 0xA71F
        sr = SR(tmp_sr)
        cycles += 16
        cpu_prefetch()

    } else {
        cpu_exception(.Privilege, opcode)
        return
    }
}

@(private="file")
cpu_ori :: proc(opcode: u16)
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            imm := i8(cpu_fetch())
            if mode == 0 {
                cycles += 4
                cpu_prefetch()
                data := u8(imm | i8(D[reg]))
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(data)
                flags8_2(data)
            } else {
                cycles += 8
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                data := ea_data | u8(imm)
                cpu_prefetch()
                bus_write8(addr, u8(data))
                flags8_2(data)
            }
        case .Word:
            imm := i16(cpu_fetch())
            if mode == 0 {
                cycles += 4
                cpu_prefetch()
                data := u16(imm | i16(D[reg]))
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(data)
                flags16_2(data)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                cycles += 8
                ea_data := cpu_get_ea_data16(mode, reg, addr)
                data := ea_data | u16(imm)
                cpu_prefetch()
                bus_write16(addr, u16(data))
                flags16_2(data)
            }
        case .Long:
            imm := u32(cpu_fetch()) << 16
            imm |= u32(cpu_fetch())
            if mode == 0 {
                cycles += 8
                cpu_prefetch()
                data := imm | D[reg]
                D[reg] = data
                flags32_2(data)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                cycles += 12
                ea_data := cpu_get_ea_data32(mode, reg, addr)
                data := ea_data | u32(imm)
                cpu_prefetch()
                bus_write32(addr, u32(data))
                flags32_2(data)
            }
    }
}

@(private="file")
cpu_andi_ccr :: proc(opcode: u16)
{
    imm := u8(cpu_fetch() & 0xFF)
    tmp_sr := u16(sr)
    ccr := u8(tmp_sr) & imm
    tmp_sr &= 0xFF00
    sr = SR(tmp_sr | u16(ccr & 0x1F))
    cycles += 16
    cpu_prefetch()
}

@(private="file")
cpu_andi_sr :: proc(opcode: u16)
{
    if sr.super {
        imm := cpu_fetch()
        tmp_sr := u16(sr) & imm
        tmp_sr &= 0xA71F
        sr = SR(tmp_sr)
        cycles += 16
        cpu_prefetch()
    } else {
        cpu_exception(.Privilege, opcode)
        return
    }
}

@(private="file")
cpu_andi :: proc(opcode: u16)
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            imm := u8(cpu_fetch())
            if mode == 0 {
                cycles += 4
                cpu_prefetch()
                data := u8(imm & u8(D[reg]))
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(data)
                flags8_2(data)
            } else {
                cycles += 8
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                data := ea_data & imm
                cpu_prefetch()
                bus_write8(addr, data)
                flags8_2(data)
            }
        case .Word:
            imm := u16(cpu_fetch())
            if mode == 0 {
                cycles += 4
                cpu_prefetch()
                data := imm & u16(D[reg])
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(data)
                flags16_2(data)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                cycles += 8
                ea_data := cpu_get_ea_data16(mode, reg, addr)
                data := ea_data & u16(imm)
                cpu_prefetch()
                bus_write16(addr, u16(data))
                flags16_2(data)
            }
        case .Long:
            imm := u32(cpu_fetch()) << 16
            imm |= u32(cpu_fetch())
            if mode == 0 {
                cycles += 8
                cpu_prefetch()
                data := imm & D[reg]
                D[reg] = data
                flags32_2(data)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                cycles += 12
                ea_data := cpu_get_ea_data32(mode, reg, addr)
                data := ea_data & imm
                cpu_prefetch()
                bus_write32(addr, data)
                flags32_2(data)
            }
    }
}

@(private="file")
cpu_eori_ccr :: proc(opcode: u16)
{
    imm := u8(cpu_fetch() & 0xFF)
    tmp_sr := u16(sr)
    ccr := u8(tmp_sr) ~ imm
    tmp_sr &= 0xFF00
    sr = SR(tmp_sr | u16(ccr & 0x1F))
    cycles += 16
    cpu_prefetch()
}

@(private="file")
cpu_eori_sr :: proc(opcode: u16)
{
    if sr.super {
        imm := cpu_fetch()
        tmp_sr := u16(sr) ~ imm
        tmp_sr &= 0xA71F
        sr = SR(tmp_sr)
        cycles += 16
        cpu_prefetch()
    } else {
        cpu_exception(.Privilege, opcode)
        return
    }
}

@(private="file")
cpu_eori :: proc(opcode: u16)
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            imm := u8(cpu_fetch())
            if mode == 0 {
                cycles += 4
                cpu_prefetch()
                data := imm ~ u8(D[reg])
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(data)
                flags8_2(data)
            } else {
                cycles += 8
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                data := ea_data ~ u8(imm)
                cpu_prefetch()
                bus_write8(addr, u8(data))
                flags8_2(data)
            }
        case .Word:
            imm := u16(cpu_fetch())
            if mode == 0 {
                cycles += 4
                cpu_prefetch()
                data := imm ~ u16(D[reg])
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(data)
                flags16_2(data)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                cycles += 8
                ea_data := cpu_get_ea_data16(mode, reg, addr)
                data := ea_data ~ u16(imm)
                cpu_prefetch()
                bus_write16(addr, u16(data))
                flags16_2(data)
            }
        case .Long:
            imm := u32(cpu_fetch()) << 16
            imm |= u32(cpu_fetch())
            if mode == 0 {
                cycles += 8
                cpu_prefetch()
                data := imm ~ D[reg]
                D[reg] = data
                flags32_2(data)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                cycles += 12
                ea_data := cpu_get_ea_data32(mode, reg, addr)
                data := ea_data ~ imm
                cpu_prefetch()
                bus_write32(addr, data)
                flags32_2(data)
            }
    }
}

@(private="file")
cpu_cmpi :: proc(opcode: u16)
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            imm := i8(cpu_fetch())
            if mode == 0 {
                cycles += 4
                cpu_prefetch()
                data, ovf := intrinsics.overflow_sub(i8(D[reg]), i8(imm))
                carry := bool((u16(u8(D[reg])) - u16(u8(imm))) >> 8)
                flags8(data, ovf, carry, false)
            } else {
                cycles += 4
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
                cycles += 4
                cpu_prefetch()
                data, ovf := intrinsics.overflow_sub(i16(D[reg]), i16(imm))
                carry := bool((u32(u16(D[reg])) - u32(u16(imm))) >> 16)
                flags16(data, ovf, carry, false)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                cycles += 4
                ea_data := cpu_get_ea_data16(mode, reg, addr)
                data, ovf := intrinsics.overflow_sub(i16(ea_data), i16(imm))
                cpu_prefetch()
                carry := bool((u32(u16(ea_data)) - u32(u16(imm))) >> 16)
                flags16(data, ovf, carry, false)
            }
        case .Long:
            imm := i32(cpu_fetch()) << 16
            imm |= i32(cpu_fetch())
            if mode == 0 {
                cycles += 6
                cpu_prefetch()
                data, ovf := intrinsics.overflow_sub(i32(D[reg]), i32(imm))
                carry := bool((u64(u32(D[reg])) - u64(u32(imm))) >> 32)
                flags32(data, ovf, carry, false)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                cycles += 4
                ea_data := cpu_get_ea_data32(mode, reg, addr)
                data, ovf := intrinsics.overflow_sub(i32(ea_data), i32(imm))
                cpu_prefetch()
                carry := bool((u64(u32(ea_data)) - u64(u32(imm))) >> 32)
                flags32(data, ovf, carry, false)
            }
    }
}

@(private="file")
cpu_subi :: proc(opcode: u16)
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            imm := i8(cpu_fetch())
            if mode == 0 {
                cycles += 4
                cpu_prefetch()
                data, ovf := intrinsics.overflow_sub(i8(D[reg]), i8(imm))
                carry := bool((u16(u8(D[reg])) - u16(u8(imm))) >> 8)
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(u8(data))
                flags8(data, ovf, carry)
            } else {
                cycles += 8
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                data, ovf := intrinsics.overflow_sub(i8(ea_data), i8(imm))
                cpu_prefetch()
                bus_write8(addr, u8(data))
                carry := bool((u16(u8(ea_data)) - u16(u8(imm))) >> 8)
                flags8(data, ovf, carry)
            }
        case .Word:
            imm := i16(cpu_fetch())
            if mode == 0 {
                cycles += 4
                cpu_prefetch()
                data, ovf := intrinsics.overflow_sub(i16(D[reg]), i16(imm))
                carry := bool((u32(u16(D[reg])) - u32(u16(imm))) >> 16)
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(u16(data))
                flags16(data, ovf, carry)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                cycles += 8
                ea_data := cpu_get_ea_data16(mode, reg, addr)
                data, ovf := intrinsics.overflow_sub(i16(ea_data), i16(imm))
                cpu_prefetch()
                bus_write16(addr, u16(data))
                carry := bool((u32(u16(ea_data)) - u32(u16(imm))) >> 16)
                flags16(data, ovf, carry)
            }
        case .Long:
            imm := i32(cpu_fetch()) << 16
            imm |= i32(cpu_fetch())
            if mode == 0 {
                cycles += 8
                cpu_prefetch()
                data, ovf := intrinsics.overflow_sub(i32(D[reg]), i32(imm))
                carry := bool((u64(u32(D[reg])) - u64(u32(imm))) >> 32)
                D[reg] = u32(data)
                flags32(data, ovf, carry)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                cycles += 12
                ea_data := cpu_get_ea_data32(mode, reg, addr)
                data, ovf := intrinsics.overflow_sub(i32(ea_data), i32(imm))
                cpu_prefetch()
                bus_write32(addr, u32(data))
                carry := bool((u64(u32(ea_data)) - u64(u32(imm))) >> 32)
                flags32(data, ovf, carry)
            }
    }
}

@(private="file")
cpu_addi :: proc(opcode: u16)
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            imm := i8(cpu_fetch())
            if mode == 0 {
                cycles += 4
                cpu_prefetch()
                data, ovf := intrinsics.overflow_add(i8(imm), i8(D[reg]))
                carry := bool((u16(u8(imm)) + u16(u8(D[reg]))) >> 8)
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(u8(data))
                flags8(data, ovf, carry)
            } else {
                cycles += 8
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                data, ovf := intrinsics.overflow_add(i8(ea_data), i8(imm))
                carry := bool((u16(ea_data) + u16(u8(imm))) >> 8)
                cpu_prefetch()
                bus_write8(addr, u8(data))
                flags8(data, ovf, carry)
            }
        case .Word:
            imm := i16(cpu_fetch())
            if mode == 0 {
                cycles += 4
                cpu_prefetch()
                data, ovf := intrinsics.overflow_add(i16(imm), i16(D[reg]))
                carry := bool((u32(u16(imm)) + u32(u16(D[reg]))) >> 16)
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(u16(data))
                flags16(data, ovf, carry)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                cycles += 8
                ea_data := cpu_get_ea_data16(mode, reg, addr)
                data, ovf := intrinsics.overflow_add(i16(ea_data), i16(imm))
                carry := bool((u32(ea_data) + u32(u16(imm))) >> 16)
                cpu_prefetch()
                bus_write16(addr, u16(data))
                flags16(data, ovf, carry)
            }
        case .Long:
            imm := i32(cpu_fetch()) << 16
            imm |= i32(cpu_fetch())
            if mode == 0 {
                cycles += 8
                cpu_prefetch()
                data, ovf := intrinsics.overflow_add(i32(imm), i32(D[reg]))
                carry := bool((u64(u32(imm)) + u64(u32(D[reg]))) >> 32)
                D[reg] = u32(data)
                flags32(data, ovf, carry)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                cycles += 12
                ea_data := cpu_get_ea_data32(mode, reg, addr)
                data, ovf := intrinsics.overflow_add(i32(ea_data), i32(imm))
                carry := bool((u64(ea_data) + u64(u32(imm))) >> 32)
                cpu_prefetch()
                bus_write32(addr, u32(data))
                flags32(data, ovf, carry)
            }
    }
}

@(private="file")
cpu_move_from_sr :: proc(opcode: u16)
{
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    if mode == 0 {
        D[reg] &= 0xFFFF0000
        D[reg] |= u32(u16(sr))
        cycles += 6
    } else {
        addr := cpu_get_address(mode, reg, .Word)
        if (addr & 1) == 1 {
            cpu_exception_addr(.Address, addr, opcode)
            return
        }
        bus_write16(addr, u16(sr))
        cycles += 12
    }
    cpu_prefetch()
}

@(private="file")
cpu_move_ccr :: proc(opcode: u16)
{
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg, .Word)
    if (addr & 1) == 1 {
        cpu_exception_addr(.Address, addr, opcode)
        return
    }
    ea_data := cpu_get_ea_data16(mode, reg, addr) & 0x1F
    tmp_sr := u16(sr)
    tmp_sr &= 0xFF00
    tmp_sr |= u16(ea_data)
    sr = SR(tmp_sr)
    cycles += 12
    cpu_prefetch()
}

@(private="file")
cpu_move_to_sr :: proc(opcode: u16)
{
    if sr.super {
        mode := (opcode >> 3) & 7
        reg := (opcode >> 0) & 7

        addr := cpu_get_address(mode, reg, .Word)
        if (addr & 1) == 1 {
            cpu_exception_addr(.Address, addr, opcode)
            return
        }
        ea_data := cpu_get_ea_data16(mode, reg, addr)
        ea_data &= 0xA71F
        sr = SR(ea_data)
    } else {
        cpu_exception(.Privilege, opcode)
        return
    }
    cycles += 12
    cpu_prefetch()
}

@(private="file")
cpu_clr :: proc(opcode: u16)
{
    size := Size((opcode >> 6) & 3)
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    switch size {
        case .Byte:
            if mode == 0 {
                D[reg] = D[reg] & 0xFFFFFF00
                cycles += 4
            } else {
                addr := cpu_get_address(mode, reg, size)
                cycles += 4
                bus_write8(addr, 0)
                cycles += 8
            }
        case .Word:
            if mode == 0 {
                D[reg] = D[reg] & 0xFFFF0000
                cycles += 4
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                cycles += 4
                bus_write16(addr, 0)
                cycles += 8
            }
        case .Long:
            if mode == 0 {
                D[reg] = 0
                cycles += 6
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
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
cpu_neg :: proc(opcode: u16)
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
                cycles += 4
                flags8(data, ovf, carry)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                data, ovf := intrinsics.overflow_sub(i8(0), i8(ea_data))
                carry := bool((u16(0) - u16(u8(ea_data))) >> 8)
                bus_write8(addr, u8(data))
                cycles += 8
                flags8(data, ovf, carry)
            }
        case .Word:
            if mode == 0 {
                data, ovf := intrinsics.overflow_sub(i16(0), i16(D[reg]))
                carry := bool((u32(0) - u32(u16(D[reg]))) >> 16)
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(u16(data))
                cycles += 4
                flags16(data, ovf, carry)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                ea_data := cpu_get_ea_data16(mode, reg, addr)
                data, ovf := intrinsics.overflow_sub(i16(0), i16(ea_data))
                carry := bool((u32(0) - u32(u16(ea_data))) >> 8)
                bus_write16(addr, u16(data))
                cycles += 8
                flags16(data, ovf, carry)
            }
        case .Long:
            if mode == 0 {
                data, ovf := intrinsics.overflow_sub(i32(0), i32(D[reg]))
                carry := bool((u64(0) - u64(u32(D[reg]))) >> 32)
                D[reg] = u32(data)
                cycles += 6
                flags32(data, ovf, carry)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                ea_data := cpu_get_ea_data32(mode, reg, addr)
                data, ovf := intrinsics.overflow_sub(i32(0), i32(ea_data))
                carry := bool((u64(0) - u64(u32(ea_data))) >> 32)
                bus_write32(addr, u32(data))
                cycles += 12
                flags32(data, ovf, carry)
            }
    }
    cpu_prefetch()
}

cpu_not :: proc(opcode: u16)
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
                cycles += 4
                flags8_2(data)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                data := ~ea_data
                bus_write8(addr, data)
                cycles += 8
                flags8_2(data)
            }
        case .Word:
            if mode == 0 {
                data := ~u16(D[reg])
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(data)
                cycles += 4
                flags16_2(data)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                ea_data := cpu_get_ea_data16(mode, reg, addr)
                data := ~ea_data
                bus_write16(addr, data)
                cycles += 8
                flags16_2(data)
            }
        case .Long:
            if mode == 0 {
                data :=  ~u32(D[reg])
                D[reg] = data
                cycles += 6
                flags32_2(data)
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                ea_data := cpu_get_ea_data32(mode, reg, addr)
                data := ~ea_data
                bus_write32(addr, data)
                cycles += 12
                flags32_2(data)
            }
    }
    cpu_prefetch()
}

@(private="file")
cpu_ext :: proc(opcode: u16)
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
    cycles += 4
    cpu_prefetch()
}

@(private="file")
cpu_swap :: proc(opcode: u16)
{
    reg := opcode & 7

    lower := (D[reg] & 0x0000FFFF) << 16
    upper := (D[reg] & 0xFFFF0000) >> 16
    data := lower | upper
    D[reg] = data
    cycles += 4
    flags32_2(data)
    cpu_prefetch()
}

@(private="file")
cpu_pea :: proc(opcode: u16)
{
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg, .Long)
    ssp -= 4
    bus_write32(ssp, addr)
    cycles = 0
    cpu_get_cycles_lea_pea(mode, reg)
    cpu_prefetch()
}

@(private="file")
cpu_illegal :: proc(opcode: u16)
{
    cpu_exception(.Illegal, opcode)
}

@(private="file")
cpu_tas :: proc(opcode: u16)
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
        cycles += 4
    } else {
        bus_write8(addr, ea_data)
        cycles += 10
    }
    cpu_prefetch()
}

@(private="file")
cpu_tst :: proc(opcode: u16)
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
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data16(mode, reg, addr)
            flags16_2(ea_data)
        case .Long:
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data32(mode, reg, addr)
            flags32_2(ea_data)
    }
    cycles += 4
    cpu_prefetch()
}

@(private="file")
cpu_trap :: proc(opcode: u16)
{
    pc += 2 //Point to the next instruction
    cpu_exception(.Trap, opcode)
}

@(private="file")
cpu_link :: proc(opcode: u16)
{
    reg := opcode & 7
    ssp -= 4
    bus_write32(ssp, cpu_Areg_get(reg))
    cpu_Areg_set(reg, ssp)
    ssp += u32(i32(i16(cpu_fetch())))
    cycles += 12
    cpu_prefetch()
}

@(private="file")
cpu_unlk :: proc(opcode: u16)
{
    reg := (opcode >> 0) & 7
    ssp = cpu_Areg_get(reg)
    cpu_Areg_set(reg, bus_read32(ssp))
    if reg != 7 {   //TODO: Why?
        ssp += 4
    }
    cycles += 12
    cpu_prefetch()
}

@(private="file")
cpu_move_usp :: proc(opcode: u16)
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
        cycles += 4
    } else {
        cpu_exception(.Privilege, opcode)
        return
    }
    cpu_prefetch()
}

@(private="file")
cpu_reset :: proc(opcode: u16)
{
    //TODO: Reset all external devices?
    if sr.super {
        cycles += 132
    } else {
        cpu_exception(.Privilege, opcode)
        return
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
cpu_stop :: proc(opcode: u16)
{
    if sr.super {
        sr = SR(cpu_fetch())
        cycles += 4
        stop = true
    } else {
        cpu_exception(.Privilege, opcode)
        return
    }
    cpu_prefetch()
}

@(private="file")
cpu_trapv :: proc(opcode: u16)
{
    if sr.v {
        pc += 2 //Point to the next instruction
        cpu_exception(.TrapV, opcode)
        return
    } else {
        cycles += 4
    }
    cpu_prefetch()
}

@(private="file")
cpu_lea :: proc(opcode: u16)
{
    reg2 := (opcode >> 9) & 7
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg, .Long)
    cpu_Areg_set(reg2, addr)
    cycles = 0
    cpu_get_cycles_lea_pea(mode, reg)
    cycles -= 8
    cpu_prefetch()
}

@(private="file")
cpu_addq :: proc(opcode: u16)
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
                cycles += 4
                flags8(data2, ovf, carry)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                cpu_prefetch()
                data2, ovf := intrinsics.overflow_add(i8(data), i8(ea_data))
                bus_write8(addr, u8(data2))
                cycles += 8
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
                cycles += 4
                flags16(data2, ovf, carry)
            } else if mode == 1 {
                areg := cpu_Areg_get(reg)
                data := u32(u16(i16(data) + i16(areg)))
                areg &= 0xFFFF0000
                areg |= data
                cpu_Areg_set(reg, areg)
                cpu_prefetch()
                cycles += 8
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                ea_data := cpu_get_ea_data16(mode, reg, addr)
                data2, ovf := intrinsics.overflow_add(i16(data), i16(ea_data))
                cpu_prefetch()
                bus_write16(addr, u16(data2))
                cycles += 8
                carry := bool((u32(data) + u32(u16(ea_data))) >> 16)
                flags16(data2, ovf, carry)
            }
        case .Long:
            if mode == 0 {
                data2, ovf := intrinsics.overflow_add(i32(data), i32(D[reg]))
                carry := bool((u64(data) + u64(u32(D[reg]))) >> 32)
                D[reg] = u32(data2)
                cpu_prefetch()
                cycles += 8
                flags32(data2, ovf, carry)
            } else if mode == 1 {
                areg := cpu_Areg_get(reg)
                data := u32(i32(data) + i32(areg))
                areg = data
                cpu_Areg_set(reg, areg)
                cpu_prefetch()
                cycles += 6
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                ea_data := cpu_get_ea_data32(mode, reg, addr)
                data2, ovf := intrinsics.overflow_add(i32(data), i32(ea_data))
                cpu_prefetch()
                bus_write32(addr, u32(data2))
                cycles += 12
                carry := bool((u64(data) + u64(u32(ea_data))) >> 32)
                flags32(data2, ovf, carry)
            }
    }
}

@(private="file")
cpu_subq :: proc(opcode: u16)
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
                cycles += 4
                flags8(data2, ovf, carry)
            } else {
                addr := cpu_get_address(mode, reg, size)
                ea_data := cpu_get_ea_data8(mode, reg, addr)
                data2, ovf := intrinsics.overflow_sub(i8(ea_data), i8(data))
                cpu_prefetch()
                bus_write8(addr, u8(data2))
                cycles += 8
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
                cycles += 4
                flags16(data2, ovf, carry)
            } else if mode == 1 {
                areg := cpu_Areg_get(reg)
                data := u32(u16(i16(areg) - i16(data)))
                areg &= 0xFFFF0000
                areg |= data
                cpu_Areg_set(reg, areg)
                cpu_prefetch()
                cycles += 8
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                ea_data := cpu_get_ea_data16(mode, reg, addr)
                data2, ovf := intrinsics.overflow_sub(i16(ea_data), i16(data))
                cpu_prefetch()
                bus_write16(addr, u16(data2))
                cycles += 8
                carry := bool((u32(ea_data) - u32(u16(data))) >> 16)
                flags16(data2, ovf, carry)
            }
        case .Long:
            if mode == 0 {
                data2, ovf := intrinsics.overflow_sub(i32(D[reg]), i32(data))
                D[reg] = u32(data2)
                cpu_prefetch()
                cycles += 8
                carry := bool((u64(D[reg]) - u64(u32(data))) >> 32)
                flags32(data2, ovf, carry)
            } else if mode == 1 {
                areg := cpu_Areg_get(reg)
                data := u32(i32(areg) - i32(data))
                cpu_Areg_set(reg, data)
                cpu_prefetch()
                cycles += 6
            } else {
                addr := cpu_get_address(mode, reg, size)
                if (addr & 1) == 1 {
                    cpu_exception_addr(.Address, addr, opcode)
                    return
                }
                ea_data := cpu_get_ea_data32(mode, reg, addr)
                data2, ovf := intrinsics.overflow_sub(i32(ea_data), i32(data))
                cpu_prefetch()
                bus_write32(addr, u32(data2))
                cycles += 12
                carry := bool((u64(ea_data) - u64(u32(data))) >> 32)
                flags32(data2, ovf, carry)
            }
    }
}

@(private="file")
cpu_divu :: proc(opcode: u16)
{
    reg := (opcode >> 9) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg2, .Word)
    if (addr & 1) == 1 {
        cpu_exception_addr(.Address, addr, opcode)
        return
    }
    ea_data := cpu_get_ea_data16(mode, reg2, addr)
    sr.c = false
    if ea_data == 0 {
        sr.z = false
        sr.v = false
        sr.n = false
        pc -= 2
        cpu_exception(.Zero, opcode)
        return
    }

    quot := D[reg] / u32(ea_data)
    remind := D[reg] % u32(ea_data)
    ovf := quot > 0xFFFF

    if !ovf {
        hdivisor := u32(ea_data) << 16
        dividend := D[reg]
        D[reg] = u32(quot) | u32(remind << 16)
        cycles += 76

        for i := 0; i < 15; i+=1
	    {
            temp := u32(dividend)
            dividend <<= 1
            if i32(temp) < 0 {
                dividend -= hdivisor
            } else {
                cycles += 4
                if dividend >= hdivisor {
                    dividend -= hdivisor
                    cycles -= 2
                }
            }
        }
        sr.n = bool(u16(quot) >> 15)
        sr.z = quot == 0
    } else {
        cycles += 10
    }
    sr.v = ovf
    cpu_prefetch()
}

@(private="file")
cpu_divs :: proc(opcode: u16)
{
    reg := (opcode >> 9) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg2, .Word)
    if (addr & 1) == 1 {
        cpu_exception_addr(.Address, addr, opcode)
        return
    }
    ea_data := cpu_get_ea_data16(mode, reg2, addr)
    sr.c = false
    if ea_data == 0 {
        cpu_exception(.Zero, opcode)
        return
    }

    cycles += 12
    dividend := D[reg]
    if i32(dividend) < 0 {
        cycles += 2
    }

    quot := i32(dividend) / i32(i16(ea_data))
    remind := i32(dividend) % i32(i16(ea_data))
    ovf := (quot > 32767) || (quot < -32767)

    if !ovf {
        D[reg] = u32(u16(quot)) | (u32(remind) << 16)
        cycles += 110
        if i16(ea_data) >= 0 {
            if i32(dividend) >= 0 {
                cycles -= 2
            } else {
                cycles += 2
            }
        }

        aquot := math.abs(i32(dividend)) / math.abs(i32(i16(ea_data)))
        for i := 0; i < 15; i += 1 {
		    if i16(aquot) >= 0 {
                cycles += 2
            }
            aquot <<= 1
	    }
        sr.n = bool(u16(quot) >> 15)
        sr.z = quot == 0
    } else {
        cycles += 4
    }
    sr.v = ovf
    cpu_prefetch()
}

@(private="file")
cpu_sub :: proc(opcode: u16)
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
                bus_write8(addr, u8(data))
                flags8(data, ovf, carry)
                cycles += 8
            } else {
                data, ovf := intrinsics.overflow_sub(i8(D[reg]), i8(ea_data))
                carry := bool((u16(u8(D[reg])) - u16(ea_data)) >> 8)
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(u8(data))
                cycles += 4
                flags8(data, ovf, carry)
            }
        case .Word:
            addr := cpu_get_address(mode, reg2, size)
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data16(mode, reg2, addr)
            cpu_prefetch()
            if dir == 1 {
                data, ovf := intrinsics.overflow_sub(i16(ea_data), i16(D[reg]))
                carry := bool((u32(ea_data) - u32(u16(D[reg]))) >> 16)
                bus_write16(addr, u16(data))
                cycles += 8
                flags16(data, ovf, carry)
            } else {
                data, ovf := intrinsics.overflow_sub(i16(D[reg]), i16(ea_data))
                carry := bool((u32(u16(D[reg])) - u32(ea_data)) >> 16)
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(u16(data))
                cycles += 4
                flags16(data, ovf, carry)
            }
        case .Long:
            addr := cpu_get_address(mode, reg2, size)
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data32(mode, reg2, addr)
            cpu_prefetch()
            if dir == 1 {
                data, ovf := intrinsics.overflow_sub(i32(ea_data), i32(D[reg]))
                carry := bool((u64(ea_data) - u64(D[reg])) >> 32)
                bus_write32(addr, ea_data - D[reg])
                cycles += 12
                flags32(data, ovf, carry)
            } else {
                data, ovf := intrinsics.overflow_sub(i32(D[reg]), i32(ea_data))
                carry := bool((u64(D[reg]) - u64(ea_data)) >> 32)
                D[reg] = u32(data)
                cycles += 6
                if mode <= 1 || (mode == 7 && reg2 == 4) {
                    cycles += 2
                }
                flags32(data, ovf, carry)
            }
    }
}

@(private="file")
cpu_alu :: proc(opcode: u16, op: Operation)
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
            switch op {
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
                bus_write8(addr, u8(data))
                cycles += 8
            } else {
                D[reg] &= 0xFFFFFF00
                D[reg] |= u32(u8(data))
                cycles += 4
            }
        case .Word:
            data: i16
            addr := cpu_get_address(mode, reg2, size)
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data16(mode, reg2, addr)
            switch op {
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
                bus_write16(addr, u16(data))
                cycles += 8
            } else {
                D[reg] &= 0xFFFF0000
                D[reg] |= u32(u16(data))
                cycles += 4
            }
        case .Long:
            data: i32
            addr := cpu_get_address(mode, reg2, size)
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data32(mode, reg2, addr)
            switch op {
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
                bus_write32(addr, u32(data))
                cycles += 12
            } else {
                D[reg] = u32(data)
                cycles += 6
                if mode <= 1 || (mode == 7 && reg2 == 4) {
                    cycles += 2
                }
            }
    }
}

@(private="file")
cpu_suba :: proc(opcode: u16)
{
    reg := (opcode >> 9) & 7
    size := (opcode >> 6) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    switch size {
        case 3:
            addr := cpu_get_address(mode, reg2, .Word)
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data16(mode, reg2, addr)
            areg := cpu_Areg_get(reg)
            data:= i32(areg) - i32(i16(ea_data))
            cpu_prefetch()
            cpu_Areg_set(reg, u32(data))
            cycles += 8
        case 7:
            addr := cpu_get_address(mode, reg2, .Long)
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data32(mode, reg2, addr)
            areg := cpu_Areg_get(reg)
            data:= i32(areg) - i32(ea_data)
            cpu_prefetch()
            cpu_Areg_set(reg, u32(data))
            cycles += 6
            if mode <= 1 || (mode == 7 && reg2 == 4) {
                cycles += 2
            }
    }
}

@(private="file")
cpu_cmpm :: proc(opcode: u16)
{
    regx := (opcode >> 9) & 7
    size := Size((opcode >> 6) & 3)
    regy := (opcode >> 0) & 7

    switch size {
        case .Byte:
            addry := cpu_get_address(3, regy, size)
            ea_datay := bus_read8(addry)
            addrx := cpu_get_address(3, regx, size)
            ea_datax := bus_read8(addrx)
            data, ovf := intrinsics.overflow_sub(i8(ea_datax), i8(ea_datay))
            carry := bool((u16(ea_datax) - u16(ea_datay)) >> 8)
            flags8(data, ovf, carry, false)
            cycles += 12
        case .Word:
            addry := cpu_get_address(3, regy, size)
            if (addry & 1) == 1 {
                cpu_exception_addr(.Address, addry, opcode)
                return
            }
            ea_datay := bus_read16(addry)
            addrx := cpu_get_address(3, regx, size)
            if (addrx & 1) == 1 {
                cycles += 4
                cpu_exception_addr(.Address, addrx, opcode)
                return
            }
            ea_datax := bus_read16(addrx)
            data, ovf := intrinsics.overflow_sub(i16(ea_datax), i16(ea_datay))
            carry := bool((u32(ea_datax) - u32(ea_datay)) >> 16)
            flags16(data, ovf, carry, false)
            cycles += 12
        case .Long:
            addry := cpu_get_address(3, regy, size)
            if (addry & 1) == 1 {
                cpu_exception_addr(.Address, addry, opcode)
                return
            }
            ea_datay := bus_read32(addry)
            addrx := cpu_get_address(3, regx, size)
            if (addrx & 1) == 1 {
                cycles += 8
                cpu_exception_addr(.Address, addrx, opcode)
                return
            }
            ea_datax := bus_read32(addrx)
            data, ovf := intrinsics.overflow_sub(i32(ea_datax), i32(ea_datay))
            carry := bool((u64(ea_datax) - u64(ea_datay)) >> 32)
            flags32(data, ovf, carry, false)
            cycles += 20
    }
    cpu_prefetch()
}

@(private="file")
cpu_cmp :: proc(opcode: u16)
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
            cycles += 4
            flags8(data, ovf, carry, false)
        case .Word:
            addr := cpu_get_address(mode, reg2, size)
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data16(mode, reg2, addr)
            cpu_prefetch()
            data, ovf := intrinsics.overflow_sub(i16(D[reg]), i16(ea_data))
            carry := bool((u32(u16(D[reg])) - u32(ea_data)) >> 16)
            cycles += 4
            flags16(data, ovf, carry, false)
        case .Long:
            addr := cpu_get_address(mode, reg2, size)
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data32(mode, reg2, addr)
            cpu_prefetch()
            data, ovf := intrinsics.overflow_sub(i32(D[reg]), i32(ea_data))
            carry := bool((u64(D[reg]) - u64(ea_data)) >> 32)
            cycles += 6
            flags32(data, ovf, carry, false)
    }
}

@(private="file")
cpu_cmpa :: proc(opcode: u16)
{
    reg := (opcode >> 9) & 7
    size := (opcode >> 6) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    switch size {
        case 3:
            addr := cpu_get_address(mode, reg2, .Word)
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := i32(i16(cpu_get_ea_data16(mode, reg2, addr)))
            areg := cpu_Areg_get(reg)
            data, ovf := intrinsics.overflow_sub(i32(areg), ea_data)
            carry := bool((u64(areg) - u64(u32(ea_data))) >> 32)
            cpu_prefetch()
            flags32(data, ovf, carry, false)
            cycles += 6
        case 7:
            addr := cpu_get_address(mode, reg2, .Long)
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data32(mode, reg2, addr)
            areg := cpu_Areg_get(reg)
            data, ovf := intrinsics.overflow_sub(i32(areg), i32(ea_data))
            carry := bool((u64(u32(areg)) - u64(ea_data)) >> 32)
            cpu_prefetch()
            cycles += 6
            flags32(data, ovf, carry, false)
    }
}

@(private="file")
cpu_eor :: proc(opcode: u16)
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
                cycles += 4
            } else {
                bus_write8(addr, data)
                cycles += 8
            }
            flags8_2(data)
        case .Word:
            addr := cpu_get_address(mode, reg2, size)
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data16(mode, reg2, addr)
            data := u16(D[reg]) ~ u16(ea_data)
            cpu_prefetch()

            if mode == 0 {
                D[reg2] &= 0xFFFF0000
                D[reg2] |= u32(data)
                cycles += 4
            } else {
                bus_write16(addr, data)
                cycles += 8
            }
            flags16_2(data)
        case .Long:
            addr := cpu_get_address(mode, reg2, size)
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data32(mode, reg2, addr)
            data := D[reg] ~ ea_data
            cpu_prefetch()

            if mode == 0 {
                D[reg2] = u32(data)
                cycles += 8
            } else {
                bus_write32(addr, data)
                cycles += 12
            }
            flags32_2(data)
    }
}

@(private="file")
cpu_mulu :: proc(opcode: u16)
{
    reg := (opcode >> 9) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg2, .Word)
    if (addr & 1) == 1 {
        cpu_exception_addr(.Address, addr, opcode)
        return
    }
    ea_data := cpu_get_ea_data16(mode, reg2, addr)
    data, ovf := intrinsics.overflow_mul(u32(ea_data), u32(u16(D[reg])))
    D[reg] = data

    cycles += 38 + u32(intrinsics.count_ones(ea_data) * 2)
    sr.c = false
    sr.v = ovf
    sr.z = data == 0
    sr.n = bool(data >> 31)
    cpu_prefetch()
}

@(private="file")
cpu_muls :: proc(opcode: u16)
{
    reg := (opcode >> 9) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    addr := cpu_get_address(mode, reg2, .Word)
    if (addr & 1) == 1 {
        cpu_exception_addr(.Address, addr, opcode)
        return
    }
    ea_data := cpu_get_ea_data16(mode, reg2, addr)
    data, ovf := intrinsics.overflow_mul(i32(i16(ea_data)), i32(i16(D[reg])))
    D[reg] = u32(data)

    src17 := u32(ea_data) << 1
    n :u32= 0
    for i in u32(0)..=15 {
        first := (1 << (i + 1)) & src17 > 0
        second := (1 << i) & src17 > 0
        if first != second do n += 1
    }

    cycles += 38 + (n * 2)
    sr.c = false
    sr.v = ovf
    sr.z = data == 0
    sr.n = bool(data >> 31)
    cpu_prefetch()
}

@(private="file")
cpu_exg :: proc(opcode: u16)
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
    cycles += 6
    cpu_prefetch()
}

@(private="file")
cpu_adda :: proc(opcode: u16)
{
    reg := (opcode >> 9) & 7
    size := (opcode >> 6) & 7
    mode := (opcode >> 3) & 7
    reg2 := (opcode >> 0) & 7

    switch size {
        case 3:
            addr := cpu_get_address(mode, reg2, .Word)
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data16(mode, reg2, addr)
            areg := cpu_Areg_get(reg)
            data:= i32(i16(ea_data)) + i32(areg)
            cpu_prefetch()
            cpu_Areg_set(reg, u32(data))
            cycles += 8
        case 7:
            addr := cpu_get_address(mode, reg2, .Long)
            if (addr & 1) == 1 {
                cpu_exception_addr(.Address, addr, opcode)
                return
            }
            ea_data := cpu_get_ea_data32(mode, reg2, addr)
            areg := cpu_Areg_get(reg)
            data:= i32(ea_data) + i32(areg)
            cpu_prefetch()
            cpu_Areg_set(reg, u32(data))
            cycles += 6
            if mode <= 1 || (mode == 7 && reg2 == 4) {
                cycles += 2
            }
    }
}

@(private="file")
cpu_asd_mem :: proc(opcode: u16)
{
    dir := (opcode >> 8) & 1
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    data: u16
    last: bool
    first: bool

    addr := cpu_get_address(mode, reg, .Word)
    if (addr & 1) == 1 {
        cpu_exception_addr(.Address, addr, opcode)
        return
    }
    ea_data := cpu_get_ea_data16(mode, reg, addr)

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
    bus_write16(addr, data)

    sr.n = bool(data >> 15)
    sr.v = sr.n ~ last
    sr.z = data == 0
    sr.x = first
    sr.c = sr.x
    cycles += 8
    cpu_prefetch()
}

@(private="file")
cpu_lsd_mem :: proc(opcode: u16)
{
    dir := (opcode >> 8) & 1
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    data: u16
    last: bool

    addr := cpu_get_address(mode, reg, .Word)
    if (addr & 1) == 1 {
        cpu_exception_addr(.Address, addr, opcode)
        return
    }
    ea_data := cpu_get_ea_data16(mode, reg, addr)

    if dir == 1 {
        data = ea_data << 1
        last = bool(ea_data >> 15)
    } else {
        last = bool(ea_data & 1)
        data = ea_data >> 1
    }
    bus_write16(addr, data)

    sr.n = bool(data >> 15)
    sr.v = false
    sr.z = data == 0
    sr.x = last
    sr.c = sr.x
    cycles += 8
    cpu_prefetch()
}

@(private="file")
cpu_roxd_mem :: proc(opcode: u16)
{
    dir := (opcode >> 8) & 1
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    data: u16
    last: bool

    addr := cpu_get_address(mode, reg, .Word)
    if (addr & 1) == 1 {
        cpu_exception_addr(.Address, addr, opcode)
        return
    }
    ea_data := cpu_get_ea_data16(mode, reg, addr)

    if dir == 1 {
        last = bool(ea_data >> 15)
        data = (ea_data << 1) | u16(sr.x)
    } else {
        last = bool(ea_data & 1)
        data = (ea_data >> 1) | (u16(sr.x) << 15)
    }
    bus_write16(addr, data)

    sr.n = bool(data >> 15)
    sr.v = false
    sr.z = data == 0
    sr.x = last
    sr.c = sr.x
    cycles += 8
    cpu_prefetch()
}

@(private="file")
cpu_rod_mem :: proc(opcode: u16)
{
    dir := (opcode >> 8) & 1
    mode := (opcode >> 3) & 7
    reg := (opcode >> 0) & 7
    data: u16
    last: bool

    addr := cpu_get_address(mode, reg, .Word)
    if (addr & 1) == 1 {
        cpu_exception_addr(.Address, addr, opcode)
        return
    }
    ea_data := cpu_get_ea_data16(mode, reg, addr)

    if dir == 1 {
        last = bool(ea_data >> 15)
        data = (ea_data << 1) | (ea_data >> 15)
    } else {
        last = bool(ea_data & 1)
        data = (ea_data >> 1) | (ea_data << 15)
    }
    bus_write16(addr, data)

    sr.n = bool(data >> 15)
    sr.v = false
    sr.z = data == 0
    sr.c = last
    cycles += 8
    cpu_prefetch()
}

@(private="file")
cpu_asd_reg :: proc(opcode: u16)
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
            cycles += 2
    }
    if cnt == 0 {
        sr.c = false
    } else {
        sr.x = last
        sr.c = sr.x
    }
    cycles += 6 + 2 * u32(cnt)
    cpu_prefetch()
}

@(private="file")
cpu_lsd_reg :: proc(opcode: u16)
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
            cycles += 2
    }
    if cnt == 0 {
        sr.c = false
    } else {
        sr.x = last
        sr.c = sr.x
    }
    sr.v = false
    cycles += 6 + 2 * u32(cnt)
    cpu_prefetch()
}

@(private="file")
cpu_roxd_reg :: proc(opcode: u16)
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
            cycles += 2
    }
    sr.v = false
    cycles += 6 + 2 * u32(cnt)
    cpu_prefetch()
}

@(private="file")
cpu_rod_reg :: proc(opcode: u16)
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
            cycles += 2
    }
    sr.v = false
    cycles += 6 + 2 * u32(cnt)
    cpu_prefetch()
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

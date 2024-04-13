package main

import "core:fmt"

@(private="file")
last_op : string

debug_cpu_draw :: proc()
{/*
    debug_text(fmt.caprintf("PC 0x%8x", pc), 10, 10)
    debug_text(fmt.caprintf("ZE (0)  0x%8x", cpu_reg_get(0)), 10, 35)
    debug_text(fmt.caprintf("AT (1)  0x%8x", cpu_reg_get(1)), 240, 35)
    debug_text(fmt.caprintf("V0 (2)  0x%8x", cpu_reg_get(2)), 10, 60)
    debug_text(fmt.caprintf("V1 (3)  0x%8x", cpu_reg_get(3)), 240, 60)
    debug_text(fmt.caprintf("A0 (4)  0x%8x", cpu_reg_get(4)), 10, 85)
    debug_text(fmt.caprintf("A1 (5)  0x%8x", cpu_reg_get(5)), 240, 85)
    debug_text(fmt.caprintf("A2 (6)  0x%8x", cpu_reg_get(6)), 10, 110)
    debug_text(fmt.caprintf("A3 (7)  0x%8x", cpu_reg_get(7)), 240, 110)
    debug_text(fmt.caprintf("T0 (8)  0x%8x", cpu_reg_get(8)), 10, 135)
    debug_text(fmt.caprintf("T1 (9)  0x%8x", cpu_reg_get(9)), 240, 135)
    debug_text(fmt.caprintf("T2 (10) 0x%8x", cpu_reg_get(10)), 10, 160)
    debug_text(fmt.caprintf("T3 (11) 0x%8x", cpu_reg_get(11)), 240, 160)
    debug_text(fmt.caprintf("T4 (12) 0x%8x", cpu_reg_get(12)), 10, 185)
    debug_text(fmt.caprintf("T5 (13) 0x%8x", cpu_reg_get(13)), 240, 185)
    debug_text(fmt.caprintf("T6 (14) 0x%8x", cpu_reg_get(14)), 10, 210)
    debug_text(fmt.caprintf("T7 (15) 0x%8x", cpu_reg_get(15)), 240, 210)
    debug_text(fmt.caprintf("S0 (16) 0x%8x", cpu_reg_get(16)), 10, 235)
    debug_text(fmt.caprintf("S1 (17) 0x%8x", cpu_reg_get(17)), 240, 235)
    debug_text(fmt.caprintf("S2 (18) 0x%8x", cpu_reg_get(18)), 10, 260)
    debug_text(fmt.caprintf("S3 (19) 0x%8x", cpu_reg_get(19)), 240, 260)
    debug_text(fmt.caprintf("S4 (20) 0x%8x", cpu_reg_get(20)), 10, 285)
    debug_text(fmt.caprintf("S5 (21) 0x%8x", cpu_reg_get(21)), 240, 285)
    debug_text(fmt.caprintf("S6 (22) 0x%8x", cpu_reg_get(22)), 10, 310)
    debug_text(fmt.caprintf("S7 (23) 0x%8x", cpu_reg_get(23)), 240, 310)
    debug_text(fmt.caprintf("T8 (24) 0x%8x", cpu_reg_get(24)), 10, 335)
    debug_text(fmt.caprintf("T9 (25) 0x%8x", cpu_reg_get(25)), 240, 335)
    debug_text(fmt.caprintf("K0 (26) 0x%8x", cpu_reg_get(26)), 10, 360)
    debug_text(fmt.caprintf("K1 (27) 0x%8x", cpu_reg_get(27)), 240, 360)
    debug_text(fmt.caprintf("GP (28) 0x%8x", cpu_reg_get(28)), 10, 385)
    debug_text(fmt.caprintf("SP (29) 0x%8x", cpu_reg_get(29)), 240, 385)
    debug_text(fmt.caprintf("FP (30) 0x%8x", cpu_reg_get(30)), 10, 410)
    debug_text(fmt.caprintf("RA (31) 0x%8x", cpu_reg_get(31)), 240, 410)
    debug_text(fmt.caprintf("HI 0x%8x", hi), 10, 435)
    debug_text(fmt.caprintf("LO 0x%8x", lo), 240, 435)

    debug_text(">", 5, 537)
    curr_op2 := debug_cpu_get_asm(curr_op)
    next_op := debug_cpu_get_asm(bus_read32(pc))

    //debug_text(fmt.caprintf(last_op), 20, 485)
    debug_text(fmt.caprintf(curr_op2), 20, 510)
    debug_text(fmt.caprintf(next_op), 20, 535)
    //last_op = curr_op2
}

@(private="file")
debug_cpu_get_asm :: proc(opcode: u32) -> string
{
    code := (opcode >> 26)
    switch code {
        case 0x00: //alu
            return debug_cpu_get_alu(opcode)
        case 0x01: //jumps
            return debug_cpu_get_jmp(opcode)
        case 0x02:
            return fmt.aprintf("j 0x%x", (pc & 0xF0000000) + (cpu_imm26(opcode) << 2))
        case 0x03:
            return fmt.aprintf("jal 0x%x", (pc & 0xF0000000) + (cpu_imm26(opcode) << 2))
        case 0x04:
            return fmt.aprintf("beq r%i, r%i, 0x%x", cpu_rs(opcode), cpu_rt(opcode), cpu_branch(opcode)+4)
        case 0x05:
            return fmt.aprintf("bne r%i, r%i, 0x%x", cpu_rs(opcode), cpu_rt(opcode), cpu_branch(opcode)+4)
        case 0x06:
            return fmt.aprintf("blez r%i, 0x%x", cpu_rs(opcode), cpu_branch(opcode)+4)
        case 0x07:
            return fmt.aprintf("bgtz r%i, 0x%x", cpu_rs(opcode), cpu_branch(opcode)+4)
        case 0x08:
            return fmt.aprintf("addi r%i, r%i, 0x%x", cpu_rt(opcode), cpu_rs(opcode), cpu_imm16_se(opcode))
        case 0x09:
            return fmt.aprintf("addiu r%i, r%i, 0x%x", cpu_rt(opcode), cpu_rs(opcode), cpu_imm16_se(opcode))
        case 0x0A:
            return fmt.aprintf("slti r%i, r%i, 0x%x", cpu_rt(opcode), cpu_rs(opcode), cpu_imm16_se(opcode))
        case 0x0B:
            return fmt.aprintf("sltiu r%i, r%i, 0x%x", cpu_rt(opcode), cpu_rs(opcode), cpu_imm16_se(opcode))
        case 0x0C:
            return fmt.aprintf("andi r%i, r%i, 0x%x", cpu_rt(opcode), cpu_rs(opcode), cpu_imm16(opcode))
        case 0x0D:
            return fmt.aprintf("ori r%i, r%i, 0x%x", cpu_rt(opcode), cpu_rs(opcode), cpu_imm16(opcode))
        case 0x0E:
            return fmt.aprintf("xori r%i, r%i, 0x%x", cpu_rt(opcode), cpu_rs(opcode), cpu_imm16(opcode))
        case 0x0F:
            return fmt.aprintf("lui r%i, 0x%x", cpu_rt(opcode), cpu_imm16(opcode) << 16)
        case 0x10..=0x13:
            return debug_cpu_get_cop(opcode)
        case 0x20:
            return fmt.aprintf("lb r%i, 0x%x", cpu_rt(opcode), u32(cpu_imm16_se(opcode)) + cpu_reg_get(cpu_rs(opcode)))
        case 0x21:
            return fmt.aprintf("lh r%i, 0x%x", cpu_rt(opcode), u32(cpu_imm16_se(opcode)) + cpu_reg_get(cpu_rs(opcode)))
        case 0x22:
            return fmt.aprintf("lwl")
        case 0x23:
            return fmt.aprintf("lw r%i, 0x%x", cpu_rt(opcode), u32(cpu_imm16_se(opcode)) + cpu_reg_get(cpu_rs(opcode)))
        case 0x24:
            return fmt.aprintf("lbu r%i, 0x%x", cpu_rt(opcode), u32(cpu_imm16_se(opcode)) + cpu_reg_get(cpu_rs(opcode)))
        case 0x25:
            return fmt.aprintf("lhu r%i, 0x%x", cpu_rt(opcode), u32(cpu_imm16(opcode)) + cpu_reg_get(cpu_rs(opcode)))
        case 0x26:
            return fmt.aprintf("lwr")
        case 0x28:
            return fmt.aprintf("sb r%i, 0x%x", cpu_rt(opcode), u32(cpu_imm16_se(opcode)) + cpu_reg_get(cpu_rs(opcode)))
        case 0x29:
            return fmt.aprintf("sh r%i, 0x%x", cpu_rt(opcode), u32(cpu_imm16_se(opcode)) + cpu_reg_get(cpu_rs(opcode)))
        case 0x2A:
            return fmt.aprintf("swl")
        case 0x2B:
            return fmt.aprintf("sw r%i, 0x%x", cpu_rt(opcode), u32(cpu_imm16_se(opcode)) + cpu_reg_get(cpu_rs(opcode)))
        case 0x2E:
            return fmt.aprintf("swr")
        case 0x30:
            return fmt.aprintf("lwc0")
        case 0x31:
            return fmt.aprintf("lwc1")
        case 0x32:
            return fmt.aprintf("lwc2")
        case 0x33:
            return fmt.aprintf("lwc3")
        case 0x38:
            return fmt.aprintf("swc0")
        case 0x39:
            return fmt.aprintf("swc1")
        case 0x3A:
            return fmt.aprintf("swc2")
        case 0x3B:
            return fmt.aprintf("swc3")
        case:
            return "Unknown opcode"
    }
    return "apa"
}

@(private="file")
debug_cpu_get_alu :: proc(opcode: u32) -> string
{
    if opcode == 0 {
        return "nop"
    }
    sub_code := opcode & 0x3F
    switch sub_code {
        case 0x00:
            return fmt.aprintf("sll r%i, r%i, 0x%x", cpu_rd(opcode), cpu_rt(opcode), cpu_imm5(opcode))
        case 0x02:
            return fmt.aprintf("srl r%i, r%i, 0x%x", cpu_rd(opcode), cpu_rt(opcode), cpu_imm5(opcode))
        case 0x03:
            return fmt.aprintf("sra r%i, r%i, 0x%x", cpu_rd(opcode), cpu_rt(opcode), cpu_imm5(opcode))
        case 0x04:
            return fmt.aprintf("sllv r%i, r%i, r%i", cpu_rd(opcode), cpu_rt(opcode), cpu_rs(opcode))
        case 0x06:
            return fmt.aprintf("srlv r%i, r%i, r%i", cpu_rd(opcode), cpu_rt(opcode), cpu_rs(opcode))
        case 0x07:
            return fmt.aprintf("srav r%i, r%i, r%i", cpu_rd(opcode), cpu_rt(opcode), cpu_rs(opcode))
        case 0x08:
            return fmt.aprintf("jr 0x%x", cpu_reg_get(cpu_rs(opcode)))
        case 0x09:
            return fmt.aprintf("jalr r%i, r%i", cpu_rs(opcode), cpu_rd(opcode))
        case 0x0C:
            return "syscall"
        case 0x0D:
            return "break"
        case 0x10:
            return fmt.aprintf("mfhi r%i", cpu_rd(opcode))
        case 0x11:
            return fmt.aprintf("mthi r%i", cpu_rs(opcode))
        case 0x12:
            return fmt.aprintf("mflo r%i", cpu_rd(opcode))
        case 0x13:
            return fmt.aprintf("mtlo r%i", cpu_rs(opcode))
        case 0x18:
            return fmt.aprintf("mult r%i, r%i", cpu_rs(opcode), cpu_rt(opcode))
        case 0x19:
            return fmt.aprintf("multu r%i, r%i", cpu_rs(opcode), cpu_rt(opcode))
        case 0x1A:
            return fmt.aprintf("div r%i, r%i", cpu_rs(opcode), cpu_rt(opcode))
        case 0x1B:
            return fmt.aprintf("divu r%i, r%i", cpu_rs(opcode), cpu_rt(opcode))
        case 0x20:
            return fmt.aprintf("add r%i, r%i, r%i", cpu_rd(opcode), cpu_rs(opcode), cpu_rt(opcode))
        case 0x21:
            return fmt.aprintf("addu r%i, r%i, r%i", cpu_rd(opcode), cpu_rs(opcode), cpu_rt(opcode))
        case 0x22:
            return fmt.aprintf("sub r%i, r%i, r%i", cpu_rd(opcode), cpu_rs(opcode), cpu_rt(opcode))
        case 0x23:
            return fmt.aprintf("subu r%i, r%i, r%i", cpu_rd(opcode), cpu_rs(opcode), cpu_rt(opcode))
        case 0x24:
            return fmt.aprintf("and r%i, r%i, r%i", cpu_rd(opcode), cpu_rs(opcode), cpu_rt(opcode))
        case 0x25:
            return fmt.aprintf("or r%i, r%i, r%i", cpu_rd(opcode), cpu_rs(opcode), cpu_rt(opcode))
        case 0x26:
            return fmt.aprintf("xor r%i, r%i, r%i", cpu_rd(opcode), cpu_rs(opcode), cpu_rt(opcode))
        case 0x27:
            return fmt.aprintf("nor r%i, r%i, r%i", cpu_rd(opcode), cpu_rs(opcode), cpu_rt(opcode))
        case 0x2A:
            return fmt.aprintf("slt r%i, r%i, r%i", cpu_rd(opcode), cpu_rs(opcode), cpu_rt(opcode))
        case 0x2B:
            return fmt.aprintf("sltu r%i, r%i, r%i", cpu_rd(opcode), cpu_rs(opcode), cpu_rt(opcode))
        case:
            return "Unknown opcode"
    }
}

@(private="file")
debug_cpu_get_jmp :: proc(opcode: u32) -> string
{
    sub_code := cpu_rt(opcode)
    switch sub_code {
        case 0x00:
            return fmt.aprintf("bltz r%i, 0x%x", cpu_rs(opcode), cpu_branch(opcode)+4)
        case 0x01:
            return fmt.aprintf("bgez r%i, 0x%x", cpu_rs(opcode), cpu_branch(opcode)+4)
        case 0x10:
            return fmt.aprintf("bltzal r%i, 0x%x", cpu_rs(opcode), cpu_branch(opcode)+4)
        case 0x11:
            return fmt.aprintf("bgezal r%i, 0x%x", cpu_rs(opcode), cpu_branch(opcode)+4)
        case:
            return "Unknown opcode"
    }
}

@(private="file")
debug_cpu_get_cop :: proc(opcode: u32) -> string
{
    code := cpu_rs(opcode)
    nn := cpu_nn(opcode)
    switch code {
        case 0x00:
            return fmt.aprintf("mfc%i r%i, cop_%i", nn, cpu_rt(opcode), cpu_rd(opcode))
        case 0x02:
            return fmt.aprintf("cfc%i r%i, cop_r%i", nn, cpu_rt(opcode), cpu_rd(opcode))
        case 0x04:
            return fmt.aprintf("mtc%i r%i, cop_r%i", nn, cpu_rt(opcode), cpu_rd(opcode))
        case 0x06:
            return fmt.aprintf("ctc%i r%i, cop_r%i", nn, cpu_rt(opcode), cpu_rd(opcode))
        case 0x08:
            return fmt.aprintf("bcf/bcn")
        case 0x10:
            sub_code := opcode & 0x3F
            switch sub_code {
                case 0x01:
                    return fmt.aprintf("cop0_tlbr")
                case 0x02:
                    return fmt.aprintf("cop0_tlbwi")
                case 0x06:
                    return fmt.aprintf("cop0_tlbwr")
                case 0x08:
                    return fmt.aprintf("cop0_tlbp")
                case 0x10:
                    return fmt.aprintf("cop0_rfe")
                case:
                    return "Unknown opcode"
            }
        case:
            return "Unknown opcode"
    }*/
}
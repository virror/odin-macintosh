package main

import "core:fmt"
import "base:intrinsics"

Via_irq :: enum {
    oneSec = 1,
    vBlank = 2,
    kbdRdy = 4,
    kbdBit = 8,
    kbdClk = 16,
    tmr2 = 32,
    tmr1 = 64,
}

@(private="file")
RegisterA :: bit_field u8 {
    sound: u8       | 3,    //Sound volume
    sndPg2: bool    | 1,    //Alternate sound buffer
    overlay: bool   | 1,    //ROM low-memory overlay
    headSel: bool   | 1,    //Disk SEL line
    page2: bool     | 1,    //Alternate screen buffer
    sccWReg: bool   | 1,    //SCC wait/request
}

@(private="file")
RegisterB :: bit_field u8 {
    TCdata: bool    | 1,    //Real-time clock serial data
    TCClk: bool     | 1,    //Real-time clock data-clock line
    TCEnb: bool     | 1,    //Real-time clock serial enable
    sw: bool        | 1,    //Mouse switch
    x2: bool        | 1,    //MouseX2
    y2: bool        | 1,    //MouseY2
    h4: bool        | 1,    //Horizontal blanking
    sndEnb: bool    | 1,    //Sound enable/disable
}

@(private="file")
PCR :: bit_field u8 {
    vBlankIc: bool  | 1,    //Vertical blanking interrupt control
    oneSecIc: u8    | 3,    //One-second interrupt control
    kbdClkIc: bool  | 1,    //Keyboard clock interrupt control
    kbdDatIc: u8    | 3,    //Keyboard data interrupt control
}

@(private="file")
ACR :: bit_field u8 {
    latchRegA: bool | 1,    //Enable/disable for input data latch for Data register A signal lines
    latchRegB: bool | 1,    //Enable/disable for input data latch for Data register B signal lines
    kbdShift: u8    | 3,    //Keyboard data bit-shift operation
    tmr2Irq: bool   | 1,    //Timer T2 interrupts
    tmr1Irq: u8     | 2,    //Timer Tl interrupts
}

@(private="file")
IRQ :: bit_field u8 {
    bits: u8        | 7,
    irq: bool       | 1,    //IRQ (all enabled VIA interrupts)
}

@(private="file")
Timer :: struct {
    enable: bool,
    counter: u16,
    latchL: u8,
    latchH: u8,
    doIrq: bool,
}

@(private="file")
registerA: RegisterA
@(private="file")
registerB: RegisterB
@(private="file")
pcr: PCR
@(private="file")
acr: ACR
@(private="file")
irqFlag: IRQ
@(private="file")
irqEnbl: IRQ
@(private="file")
kbdShift: u8
@(private="file")
regADir: u8
@(private="file")
regBDir: u8
@(private="file")
tmr1: Timer
@(private="file")
tmr2: Timer

via_init :: proc()
{
    registerA.overlay = true
    registerB.sw = true
    tmr1.doIrq = false
    tmr2.doIrq = false
}

via_step :: proc(cycles: u32)
{
    via_update_tmr1(cycles)
    via_update_tmr2(cycles)
    rtc_update_1sec(cycles)
}

via_read :: proc(size: u8, address: u32) -> u32
{
    if size != 8 {
        fmt.println("Wrong size on VIA read?")
    }
    switch address {
        case 0xEFE1FE:      //register B
            via_clear_irq(.kbdClk)
            via_clear_irq(.kbdBit)
            return u32(registerB)
        case 0xEFE5FE:      //register B direction
            return u32(regBDir)
        case 0xEFE7FE:      //register A direction
            return u32(regADir)
        case 0xEFE9FE:      //timer 1 counter (low byte)
            via_clear_irq(.tmr1)
            return u32(u8(tmr1.counter))
        case 0xEFEBFE:      //timer 1 counter (high byte)
            return u32(tmr1.counter >> 8)
        case 0xEFEDFE:      //timer 1 latch (low byte)
            return u32(tmr1.latchL)
        case 0xEFEFFE:      //timer 1 latch (high byte)
            return u32(tmr1.latchH)
        case 0xEFF1FE:      //timer 2 counter (low byte)
            via_clear_irq(.tmr2)
            return u32(u8(tmr2.counter))
        case 0xEFF3FE:      //timer 2 counter (high byte)
            return u32(tmr2.counter >> 8)
        case 0xEFF5FE:      //shift register (keyboard)
            via_clear_irq(.kbdRdy)
            return u32(kbdShift)
        case 0xEFF7FE:      //auxiliary control register
            return u32(acr)
        case 0xEFF9FE:      //peripheral control register
            return u32(pcr)
        case 0xEFFBFE:      //interrupt flag register
            return u32(irqFlag)
        case 0xEFFDFE:      //interrupt enable register
            return u32(irqEnbl) | 0x80
        case 0xEFFFFE:      //register A
            via_clear_irq(.oneSec)
            via_clear_irq(.vBlank)
            //fmt.printf("sel %d\n", int(registerA.headSel))
            return u32(registerA)
        case:
            fmt.println("Invalid VIA register read")
    }
    return 0
}

via_write :: proc(size: u8, address: u32, value: u32)
{
    if size != 8 {
        fmt.println("Wrong size on VIA write?")
    }
    switch address {
        case 0xEFE1FE:  //register B
            rtc_run(u8(value))
            via_clear_irq(.kbdClk)
            via_clear_irq(.kbdBit)
            registerB = RegisterB(value)
        case 0xEFE5FE:  //register B direction
            regBDir = u8(value)
        case 0xEFE7FE:  //register A direction
            regADir = u8(value)
        case 0xEFE9FE:  //timer 1 counter (low byte)
            tmr1.latchL = u8(value)
        case 0xEFEBFE:  //timer 1 counter (high byte)
            tmr1.counter = (u16(value) << 8)
            tmr1.counter |= u16(tmr1.latchL)
            via_clear_irq(.tmr1)
            tmr1.doIrq = true
            tmr1.enable = true
        case 0xEFEDFE:  //timer 1 latch (low byte)
            tmr1.latchL = u8(value)
        case 0xEFEFFE:  //timer 1 latch (high byte)
            tmr1.latchH = u8(value)
            via_clear_irq(.tmr1)
        case 0xEFF1FE:  //timer 2 counter (low byte)
            tmr2.latchL = u8(value)
        case 0xEFF3FE:  //timer 2 counter (high byte)
            tmr2.counter = (u16(value) << 8)
            tmr2.counter |= u16(tmr2.latchL)
            via_clear_irq(.tmr2)
            tmr2.doIrq = true
            tmr2.enable = true
        case 0xEFF5FE:  //shift register (keyboard)
            via_clear_irq(.kbdRdy)
            kbdShift = u8(value)
        case 0xEFF7FE:  //auxiliary control register
            acr = ACR(value)
        case 0xEFF9FE:  //peripheral control register
            pcr = PCR(value)
        case 0xEFFBFE:  //interrupt flag register
            irqFlag = IRQ(u8(irqFlag) & ~u8(value))
            irqFlag.irq = bool(irqFlag & irqEnbl)
        case 0xEFFDFE:  //interrupt enable register
            if (value & 0x80) > 0 { //Set
                irqEnbl.bits |= u8(value)
            } else {                //Clear
                irqEnbl.bits &= u8(~value)
            }
        case 0xEFFFFE:  //register A
            via_clear_irq(.oneSec)
            via_clear_irq(.vBlank)
            registerA = RegisterA(value)
            iwm_set_sel(registerA.headSel)
        case:
            fmt.println("Invalid VIA register write")
    }
}

via_clear_irq :: proc(bit: Via_irq)
{
    irqFlag.bits &= ~u8(bit)
    irqFlag.irq = (irqEnbl.bits > 0)
}

via_get_regA :: proc() -> RegisterA
{
    return registerA
}

via_set_h4 :: proc(enable: bool)
{
    registerB.h4 = enable
}

via_set_TCdata :: proc(data: bool)
{
    registerB.TCdata = data
}

via_mouse_btn :: proc(state: bool)
{
    registerB.sw = !state
}

via_irq :: proc(irq: Via_irq)
{
    irqFlag.bits |= u8(irq)
    if (u8(irq) & irqEnbl.bits) > 0 {
        irqFlag.irq = true
        cpu_interrupt(1)
    }
}

@(private="file")
via_update_tmr1 :: proc(cycles: u32)
{
    if tmr1.enable {
        switch acr.tmr1Irq {
            case 0:
                value, ovf := intrinsics.overflow_sub(tmr1.counter, u16(cycles))
                tmr1.counter = value
                if ovf && tmr1.doIrq {
                    via_irq(.tmr1)
                    tmr1.doIrq = false
                }
            case 1:
                value, ovf := intrinsics.overflow_sub(tmr1.counter, u16(cycles))
                tmr1.counter = value
                if ovf {
                    via_irq(.tmr1)
                    tmr1.counter = u16(tmr1.latchH << 8)
                    tmr1.counter |= u16(tmr1.latchL)
                }
            case 2://?
            case 3://?
        }
    }
}

@(private="file")
via_update_tmr2 :: proc(cycles: u32)
{
    if tmr2.enable {
        if acr.tmr2Irq {
            //?
        } else {
            value, ovf := intrinsics.overflow_sub(tmr2.counter, u16(cycles))
            tmr2.counter = value
            if ovf && tmr2.doIrq {
                via_irq(.tmr2)
                tmr2.doIrq = false
            }
        }
    }
}

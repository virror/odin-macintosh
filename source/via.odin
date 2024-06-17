package main

import "core:fmt"

@(private="file")
RegisterA :: bit_field u8 {
    sound: bool     | 3,    //Sound volume
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
    oneSecIc: bool  | 3,    //One-second interrupt control
    kbdClkIc: bool  | 1,    //Keyboard clock interrupt control
    kbdDatIc: bool  | 3,    //Keyboard data interrupt control
}

@(private="file")
ACR :: bit_field u8 {
    tmr1Irq: bool   | 1,    //Timer Tl interrupts
    tmr2Irq: bool   | 1,    //Timer T2 interrupts
    kbdShift: bool  | 3,    //Keyboard data bit-shift operation
    latchRegA: bool | 1,    //Enable/disable for input data latch for Data register B signal lines
    latchRegB: bool | 2,    //Enable/disable for input data latch for Data register A signal lines
}

@(private="file")
IRQ :: bit_field u8 {
    oneSec: bool    | 1,    //One-second interrupt
    vBlank: bool    | 1,    //Vertical blanking interrupt
    kbdRdy: bool    | 1,    //Keyboard data ready
    kbdBit: bool    | 1,    //Keyboard data bit
    kbdClk: bool    | 1,    //Keyboard clock
    tmr2: bool      | 1,    //Timer 2
    tmr1: bool      | 1,    //Timer 1
    irq: bool       | 1,    //IRQ (all enabled VIA interrupts)
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
tmr1Low: u8
@(private="file")
tmr1High: u8
@(private="file")
tmr2Low: u8
@(private="file")
tmr2High: u8
@(private="file")
tmr1LatchLow: u8
@(private="file")
tmr1LatchHigh: u8
@(private="file")
regADir: u8
@(private="file")
regBDir: u8

via_init :: proc()
{
    registerA.overlay = true
}

via_read :: proc(size: u8, address: u32) -> u32
{
    if size != 8 {
        fmt.println("Wrong size on VIA read?")
    }
    switch address {
        case 0xEFE1FE:      //register B
            return u32(registerB)
        case 0xEFE5FE:      //register B direction
            return u32(regBDir)
        case 0xEFE7FE:      //register A direction
            return u32(regADir)
        case 0xEFE9FE:      //timer 1 counter (low byte)
            return u32(tmr1Low)
        case 0xEFEBFE:      //timer 1 counter (high byte)
            return u32(tmr1High)
        case 0xEFEDFE:      //timer 1 latch (low byte)
            return u32(tmr1LatchLow)
        case 0xEFEFFE:      //timer 1 latch (high byte)
            return u32(tmr1LatchHigh)
        case 0xEFF1FE:      //timer 2 counter (low byte)
            return u32(tmr2Low)
        case 0xEFF3FE:      //timer 2 counter (high byte)
            return u32(tmr2High)
        case 0xEFF5FE:      //shift register (keyboard)
            return u32(kbdShift)
        case 0xEFF7FE:      //auxiliary control register
            return u32(acr)
        case 0xEFF9FE:      //peripheral control register
            return u32(pcr)
        case 0xEFFBFE:      //interrupt flag register
            return u32(irqFlag)
        case 0xEFFDFE:      //interrupt enable register
            return u32(irqEnbl)
        case 0xEFFFFE:      //register A
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
            registerB = RegisterB(value)
        case 0xEFE5FE:  //register B direction
            regBDir = u8(value)
        case 0xEFE7FE:  //register A direction
            regADir = u8(value)
        case 0xEFE9FE:  //timer 1 counter (low byte)
            tmr1Low = u8(value)
        case 0xEFEBFE:  //timer 1 counter (high byte)
            tmr1High = u8(value)
        case 0xEFEDFE:  //timer 1 latch (low byte)
            tmr1LatchLow = u8(value)
        case 0xEFEFFE:  //timer 1 latch (high byte)
            tmr1LatchLow = u8(value)
        case 0xEFF1FE:  //timer 2 counter (low byte)
            tmr2Low = u8(value)
        case 0xEFF3FE:  //timer 2 counter (high byte)
            tmr2High = u8(value)
        case 0xEFF5FE:  //shift register (keyboard)
            kbdShift = u8(value)
        case 0xEFF7FE:  //auxiliary control register
            acr = ACR(value)
        case 0xEFF9FE:  //peripheral control register
            pcr = PCR(value)
        case 0xEFFBFE:  //interrupt flag register
            irqFlag = IRQ(value)
        case 0xEFFDFE:  //interrupt enable register
            irqEnbl = IRQ(value)
        case 0xEFFFFE:  //register A
            registerA = RegisterA(value)
        case:
            fmt.println("Invalid VIA register write")
    }
}

via_get_regA :: proc() -> RegisterA
{
    return registerA
}

via_set_h4 :: proc(enable: bool)
{
    registerB.h4 = enable
}
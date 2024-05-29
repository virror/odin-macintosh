package main

//import "core:fmt"

@(private="file")
RegisterA :: bit_field u8 {
    sccWReg: bool   | 1,    //SCC wait/request
    page2: bool     | 1,    //Alternate screen buffer
    headSel: bool   | 1,    //Disk SEL line
    overlay: bool   | 1,    //ROM low-memory overlay
    sndPg2: bool    | 1,    //Alternate sound buffer
    sound: bool     | 3,    //Sound volume
}

@(private="file")
RegisterB :: bit_field u8 {
    sndEnb: bool    | 1,    //Sound enable/disable
    h4: bool        | 1,    //Horizontal blanking
    y2: bool        | 1,    //MouseY2
    x2: bool        | 1,    //MouseX2
    sw: bool        | 1,    //Mouse switch
    TCEnb: bool     | 1,    //Real-time clock serial enable
    TCClk: bool     | 1,    //Real-time clock data-clock line
    TCdata: bool    | 1,    //Real-time clock serial data
}

@(private="file")
PCR :: bit_field u8 {
    a: bool         | 3,    //Keyboard data interrupt control
    b: bool         | 1,    //Keyboard clock interrupt control
    c: bool         | 3,    //One-second interrupt control
    d: bool         | 1,    //Vertical blanking interrupt control
}

@(private="file")
IRQ :: bit_field u8 {
    irq: bool       | 1,    //IRQ (all enabled VIA interrupts)
    tmr1: bool      | 1,    //Timer 1
    tmr2: bool      | 1,    //Timer 2
    kbdClk: bool    | 1,    //Keyboard clock
    kbdBit: bool    | 1,    //Keyboard data bit
    kbdRdy: bool    | 1,    //Keyboard data ready
    vBlank: bool    | 1,    //Vertical blanking interrupt
    oneSec: bool    | 1,    //One-second interrupt
}

@(private="file")
registerA: RegisterA
@(private="file")
registerB: RegisterB
@(private="file")
pcr: PCR
@(private="file")
irq: IRQ

via_init :: proc()
{
    registerA.overlay = true
}

via_get_overlay :: proc() -> bool
{
    return registerA.overlay
}
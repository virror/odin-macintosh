package main

import "core:fmt"

Disk_status :: enum {
    DIRTN = 0,
    CSTIN = 1,
    STEP = 2,
    WRTPRT = 3,
    MOTORON = 4,
    TKO = 5,
    TACH = 7,
    RDDATA0 = 8,
    RDDATA1 = 9,
    SIDES = 12,
    DRVIN = 15,
}

Disk_ctrl :: enum {
    STEPIN = 0,
    STEPOUT = 1,
    RESET = 3,
    STEP = 4,
    MOTORON = 8,
    MOTOROFF = 9,
    EJECT = 13,
}

@(private="file")
Mode :: bit_field u8 {
    latch: bool     | 1,    //Latch mode
    shake: bool     | 1,    //Handshake protocol
    timer: bool     | 1,    //Motor-off timer
    time: bool      | 1,    //Bit cell time
    speed: bool     | 1,    //Clock speed
    reserved: u8    | 3,    //Reserved
}

@(private="file")
Status :: bit_field u8 {
    a: bool         | 1,    //
    b: bool         | 1,    //
    c: bool         | 1,    //
    d: bool         | 1,    //
    e: bool         | 1,    //
    drive: bool     | 1,    //Drive enabled
    reserved: bool  | 1,    //Reserved
    sense: bool     | 1,    //Sense input
}

@(private="file")
Handshake :: bit_field u8 {
    reserved: bool  | 6,    //Reserved
    underrun: bool  | 1,    //Under-run
    ready: bool     | 1,    //Register Ready
}

@(private="file")
mode: Mode
@(private="file")
status: Status
@(private="file")
handshake: Handshake
ca0: bool
ca1: bool
ca2: bool
lstrb: bool
enbl: bool
select: bool
q6: bool
q7: bool
sel: bool
motor_on: bool
step_dir: bool

iwm_init :: proc()
{
    mode = Mode(0x1F)
    handshake = Handshake(0xFF)
}

iwm_read :: proc(size: u8, address: u32) -> u32
{
    if size != 8 {
        fmt.println("Wrong size on IWM read?")
    }
    switch address {
        case 0xDFE1FF:  //CA0 off
            ca0 = false
            return 0
        case 0xDFE3FF:  //CA0 on
            ca0 = true
            return 0
        case 0xDFE5FF:  //CA1 off
            ca1 = false
            return 0
        case 0xDFE7FF:  //CA1 on
            ca1 = true
            return 0
        case 0xDFE9FF:  //CA2 off
            ca2 = false
            return 0
        case 0xDFEBFF:  //CA2 on
            ca2 = true
            return 0
        case 0xDFEDFF:  //LSTRB off
            lstrb = false
            return 0
        case 0xDFEFFF:  //LSTRB on
            lstrb = true
            iwm_write_drive()
            return 0
        case 0xDFF1FF:  //disk enable off
            enbl = false
            return 0
        case 0xDFF3FF:  //disk enable on
            enbl = true
            return 0
        case 0xDFF5FF:  //int drive
            select = false
            return 0
        case 0xDFF7FF:  //ext drive
            select = true
            return 0
        case 0xDFF9FF:  //Q6 off
            q6 = false
            return 0
        case 0xDFFBFF:  //Q6 on
            q6 = true
            return 0
        case 0xDFFDFF:  //Q7 off
            q7 = false
            return u32(iwm_handle_regs())
        case 0xDFFFFF:  //Q7 on
            q7 = true
            return 0
    }
    return 0
}

iwm_write :: proc(size: u8, address: u32, value: u32)
{
    fmt.println("iwm_write")
    if size != 8 {
        fmt.println("Wrong size on IWM read?")
    }
    switch address {
        case 0xDFE1FF:  //CA0 off

        case 0xDFE3FF:  //CA0 on

        case 0xDFE5FF:  //CA1 off

        case 0xDFE7FF:  //CA1 on

        case 0xDFE9FF:  //CA2 off

        case 0xDFEBFF:  //CA2 on

        case 0xDFEDFF:  //LSTRB off

        case 0xDFEFFF:  //LSTRB on

        case 0xDFF1FF:  //disk enable off

        case 0xDFF3FF:  //disk enable on

        case 0xDFF5FF:  //int drive

        case 0xDFF7FF:  //ext drive

        case 0xDFF9FF:  //Q6 off

        case 0xDFFBFF:  //Q6 on

        case 0xDFFDFF:  //Q7 off

        case 0xDFFFFF:  //Q7 on

    }
}

iwm_handle_regs :: proc() -> u8
{
    q6q7 := u8(q7) | u8(q6) << 1
    fmt.println(q6q7)
    if enbl {
        fmt.println("Disc drive read")
        switch q6q7 {
            case 2: //Read status bits
                disk_reg := u8(sel) | (u8(ca0) << 1) | (u8(ca1) << 2) | (u8(ca2) << 3)
                fmt.println(disk_reg)
                #partial switch Disk_status(disk_reg) {
                    case .CSTIN:
                        status.sense = false
                    case .MOTORON:
                        status.sense = motor_on
                    case .SIDES:
                        status.sense = true
                    case .TKO:
                        status.sense = false
                    case .TACH:
                        status.sense = true
                    case Disk_status(14):
                        //??
                        status.sense = false
                    case:
                        panic("Unimplemented IWM disk_reg read")
                }
                return u8(status)
        }
    } else {
        fmt.println("IWM Regs")
        switch q6q7 {
            case 0:
                if enbl {
                    // Read data
                } else {
                    return 0xFF
                }
            case 1:
                return u8(handshake)
            case 2:
                return u8(status) | (u8(mode) & 0x1F)
            case 3:
                if enbl {
                    //Write data
                } else {
                    //Write mode
                }
        }
    }
    return 0
}

iwm_write_drive :: proc()
{
    fmt.println("Disc drive write")
    disk_reg := u8(ca2) | (u8(sel) << 1) | (u8(ca0) << 2) | (u8(ca1) << 3)
    fmt.println(disk_reg)
    switch Disk_ctrl(disk_reg) {
        case .MOTORON:
            motor_on = true
        case .MOTOROFF:
            motor_on = false
        case .EJECT:
            //Eject
        case .STEPIN:
            step_dir = false
        case .STEPOUT:
            step_dir = true
        case .STEP:
            //Step
        case .RESET:
            //Reset disk-switched flag?
        case:
            panic("Unimplemented IWM disk_reg write")
    }

}

iwm_set_sel :: proc(new_sel: bool)
{
    sel = new_sel
}

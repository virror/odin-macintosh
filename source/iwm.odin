package main

import "core:fmt"

Disk_status :: enum {
    DIRTN = 0,
    CSTIN = 1,
    STEP = 2,
    WRTPRT = 3,
    MOTORON = 4,
    TKO = 5,
    SWITCHED = 6,
    TACH = 7,
    RDDATA0 = 8,
    RDDATA1 = 9,
    SIDES = 12,
    READY = 14,
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
    mode: bool      | 5,    //Lower mode bits
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
Drive :: struct {
    motor_off: bool,
    step_dir: bool,
    track: u8,
    switched: bool,
    enable: bool,
    disc: bool,
}

@(private="file")
mode: Mode
@(private="file")
status: Status
@(private="file")
handshake: Handshake
@(private="file")
drive: [2]Drive
ca0: bool
ca1: bool
ca2: bool
lstrb: bool
enbl: bool
select: u8
q6: bool
q7: bool
sel: bool

iwm_init :: proc()
{
    mode = Mode(0x1F)
    handshake = Handshake(0xFF)

    drive[0].motor_off = true
    drive[0].switched = true
    drive[0].enable = true
    drive[0].disc = true

    drive[1].motor_off = true
    drive[1].switched = true
    drive[1].enable = false
    drive[1].disc = false
}

iwm_read :: proc(size: u8, address: u32) -> u32
{
    if size != 8 {
        fmt.println("Wrong size on IWM read?")
    }
    switch address {
        case 0xDFE1FF:  //CA0 off
            ca0 = false
        case 0xDFE3FF:  //CA0 on
            ca0 = true
        case 0xDFE5FF:  //CA1 off
            ca1 = false
        case 0xDFE7FF:  //CA1 on
            ca1 = true
        case 0xDFE9FF:  //CA2 off
            ca2 = false
        case 0xDFEBFF:  //CA2 on
            ca2 = true
        case 0xDFEDFF:  //LSTRB off
            lstrb = false
        case 0xDFEFFF:  //LSTRB on
            lstrb = true
            iwm_write_drive()
        case 0xDFF1FF:  //disk enable off
            enbl = false
            status.drive = false    //TODO: Only false if all drives are off
        case 0xDFF3FF:  //disk enable on
            enbl = true
            status.drive = true
        case 0xDFF5FF:  //int drive
            select = 0
        case 0xDFF7FF:  //ext drive
            select = 1
        case 0xDFF9FF:  //Q6 off
            q6 = false
        case 0xDFFBFF:  //Q6 on
            q6 = true
        case 0xDFFDFF:  //Q7 off
            q7 = false
            return u32(iwm_handle_regs())
        case 0xDFFFFF:  //Q7 on
            q7 = true
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

@(private="file")
iwm_handle_regs :: proc() -> u8
{
    q6q7 := u8(q7) | u8(q6) << 1
    switch q6q7 {
        case 0:
            if enbl {
                fmt.println("IWM read data")
                // Read data
            }
        case 1:
            fmt.println("IWM handshake")
            return u8(handshake)
        case 2:
            if enbl {
                fmt.println("IWM read drive")
                status.sense = iwm_read_status()
                return u8(status) | (u8(mode) & 0x1F)
            } else {
                fmt.println("IWM read status")
                return u8(status) | (u8(mode) & 0x1F)
            }
        case:
            fmt.println("IWM read unknown")
            return 0xFF
    }
    return 0
}

@(private="file")
iwm_read_status :: proc() -> bool
{
    disk_reg := u8(sel) | (u8(ca0) << 1) | (u8(ca1) << 2) | (u8(ca2) << 3)
    fmt.println(Disk_status(disk_reg))
    switch Disk_status(disk_reg) {
        case .DIRTN:
            return drive[select].step_dir
        case .CSTIN:
            return false
        case .STEP:
            return true
        case .WRTPRT:
            return true 
        case .MOTORON:
            return drive[select].motor_off
        case .TKO:
            return !(drive[select].track == 0)
        case .SWITCHED:
            return drive[select].switched
        case .TACH:
            return true
        case .RDDATA0:
        case .RDDATA1:
        case .SIDES:
            return false
        case .DRVIN:
            return false
        case .READY:    // Alternative explanation: "Disk ready for reading?" (0 = ready)
            return false
        case:
            panic("Unimplemented IWM disk_reg read")
    }
    return false
}

@(private="file")
iwm_write_drive :: proc()
{
    fmt.println("Disc drive write")
    disk_reg := u8(ca2) | (u8(sel) << 1) | (u8(ca0) << 2) | (u8(ca1) << 3)
    fmt.println(Disk_ctrl(disk_reg))
    switch Disk_ctrl(disk_reg) {
        case .STEPIN:
            drive[select].step_dir = false
        case .STEPOUT:
            drive[select].step_dir = true
        case .RESET:
            drive[select].switched = false
        case .STEP:
            if drive[select].step_dir && drive[select].track > 0{
                drive[select].track -= 1
            } else if drive[select].track < 79{ //TODO: Check this
                drive[select].track += 1
            }
        case .MOTORON:
            if drive[select].disc {
                drive[select].motor_off = false
            }
        case .MOTOROFF:
            drive[select].motor_off = true
        case .EJECT:
            //Eject
        case:
            panic("Unimplemented IWM disk_reg write")
    }

}

iwm_set_sel :: proc(new_sel: bool)
{
    sel = new_sel
}

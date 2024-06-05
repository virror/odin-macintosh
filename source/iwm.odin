package main

import "core:fmt"

iwm_read :: proc(size: u8, address: u32) -> u32
{
    if size != 8 {
        fmt.println("Wrong size on IWM read?")
    }
    switch address {
        case 0xDFE1FF:  //CA0 off
            return 0
        case 0xDFE3FF:  //CA0 on
            return 0
        case 0xDFE5FF:  //CA1 off
            return 0
        case 0xDFE7FF:  //CA1 on
            return 0
        case 0xDFE9FF:  //CA2 off
            return 0
        case 0xDFEBFF:  //CA2 on
            return 0
        case 0xDFEDFF:  //LSTRB off
            return 0
        case 0xDFEFFF:  //LSTRB on
            return 0
        case 0xDFF1FF:  //disk enable off
            return 0
        case 0xDFF3FF:  //disk enable on
            return 0
        case 0xDFF5FF:  //int drive
            return 0
        case 0xDFF7FF:  //ext drive
            return 0
        case 0xDFF9FF:  //Q6 off
            return 0
        case 0xDFFBFF:  //Q6 on
            return 0
        case 0xDFFDFF:  //Q7 off
            return 0
        case 0xDFFFFF:  //Q7 on
            return 0
    }
    return 0
}

iwm_write :: proc(size: u8, address: u32, value: u32)
{
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
package main

import "core:fmt"

@(private="file")
readBctrl: u8
@(private="file")
readAtrl: u8
@(private="file")
readBdata: u8
@(private="file")
readAdata: u8
@(private="file")
writeBctrl: u8
@(private="file")
writeActrl: u8
@(private="file")
writeBdata: u8
@(private="file")
writeAdata: u8

scc_read :: proc(address: u32) -> u32
{
    switch address {
        case 0x9FFFF8:      //read B ctrl
            return u32(readBctrl)
        case 0x9FFFFA:      //read A ctrl
            return u32(readAtrl)
        case 0x9FFFFC:      //read B data
            return u32(readBdata)
        case 0x9FFFFE:      //read A data
            return u32(readAdata)
        case 0xBFFFF9:      //write B ctrl
            return u32(writeBctrl)
        case 0xBFFFFB:      //write A ctrl
            return u32(writeActrl)
        case 0xBFFFFD:      //write B data
            return u32(writeBdata)
        case 0xBFFFFF:      //write A data
            return u32(writeAdata)
        case:
            fmt.println("Invalid SCC register read")
    }
    return 0
}

scc_write :: proc(address: u32, value: u32)
{
    switch address {
        case 0x9FFFF8:  //read B ctrl
            readBctrl = u8(value)
        case 0x9FFFFA:  //read A ctrl
            readAtrl = u8(value)
        case 0x9FFFFC:  //read B data
            readBdata = u8(value)
        case 0x9FFFFE:  //read A data
            readAdata = u8(value)
        case 0xBFFFF9:  //write B ctrl
            writeBctrl = u8(value)
        case 0xBFFFFB:  //write A ctrl
            writeActrl = u8(value)
        case 0xBFFFFD:  //write B data
            writeBdata = u8(value)
        case 0xBFFFFF:  //write A data
            writeAdata = u8(value)
        case:
            fmt.println("Invalid VIA register write")
    }
}

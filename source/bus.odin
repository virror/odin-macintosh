package main

import "core:fmt"
import "core:os"

ram_mem: [0x1000000]u8
@(private="file")
rom_mem: [0x20000]u8

bus_init :: proc()
{
    file, err := os.open("Macintosh 512K.ROM", os.O_RDONLY)
    assert(err == 0, "Failed to open bios")
    _, err2 := os.read(file, rom_mem[0x00000:0x10000])
    assert(err2 == 0, "Failed to read bios data")
    os.close(file)
}

bus_read32 :: proc(address: u32) -> u32
{
    switch address {
        //case 0x000000..<0x080000:       //RAM
        //case 0x400000..<0x420000:       //ROM
        //    return (cast(^u32)&rom_mem[address - 0x400000])^
        /*case 0x900000..<0xA00000:       //SCC_R/Phase adjust
        case 0xB00000..<0xC00000:       //SCC_W/Phase adjust
        case 0xD00000..<0xE00000:       //IWM
        case 0xE80000..<0xF00000:       //VIA
        case 0xF00000..<0xF80000:       //Phase read*/
        case:                           //Rest of memory
            fmt.println(address)
            panic("Unused mem access")
    }
    return 0
}

bus_read16 :: proc(address: u32) -> u16
{
    switch address {
        //case 0x400000..<0x420000:       //ROM
            //return (cast(^u16)&rom_mem[address - 0x400000])^
            //return (u16(rom_mem[address - 0x400000 + 1]) | u16(rom_mem[address - 0x400000]) << 8)
        case:                           //Rest of memory
            return u16(ram_mem[address + 1]) | (u16(ram_mem[address]) << 8)
            //fmt.println(address)
            //panic("Unused mem access")
    }
    return 0
}

bus_read8 :: proc(address: u32) -> u8
{
    switch address {
        case:                           //Rest of memory
            fmt.println(address)
            panic("Unused mem access")
    }
    return 0
}

bus_write32 :: proc(address: u32, value: u32)
{
    switch address {
        case:                           //Rest of memory
            fmt.println(address)
            panic("Unused mem access")
    }
}

bus_write16 :: proc(address: u32, value: u16)
{
    switch address {
        case:                           //Rest of memory
            ram_mem[address + 1] = u8(value & 0xFF)
            ram_mem[address + 0] = u8((value >> 8) & 0xFF)
            //fmt.println(address)
            //panic("Unused mem access")
    }
}

bus_write8 :: proc(address: u32, value: u8)
{
    switch address {
        case:                           //Rest of memory
            fmt.println(address)
            panic("Unused mem access")
    }
}

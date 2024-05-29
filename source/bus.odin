package main

import "core:fmt"
import "core:os"

@(private="file")
ram_mem: [0x80000]u8
@(private="file")
rom_mem: [0x20000]u8

bus_init :: proc()
{
    fmt.println("Bus init") //Get rid of unused fmt error
    file, err := os.open("Macintosh 512K.ROM", os.O_RDONLY)
    assert(err == 0, "Failed to open bios")
    _, err2 := os.read(file, rom_mem[0x00000:0x10000])
    assert(err2 == 0, "Failed to read bios data")
    os.close(file)
}

bus_read :: proc(size: u8, address: u32) -> u32
{
    addr := address & 0xFFFFFF
    when TEST_ENABLE {
        return test_read(size, addr)
    } else {
        if via_get_overlay() {
            switch addr {
                case 0x000000..<0x080000:       //ROM
                    return bus_read_rom(size, addr)
                case 0x400000..<0x420000:       //ROM
                    addr -= 0x400000
                    return bus_read_rom(size, addr)
                case 0x600000..<0x680000:       //RAM
                    return bus_read_ram(size, addr)
                /*case 0x900000..<0xA00000:       //SCC_R/Phase adjust
                case 0xB00000..<0xC00000:       //SCC_W/Phase adjust
                case 0xD00000..<0xE00000:       //IWM*/
                case 0xE80000..<0xF00000:       //VIA
                    return via_read(size, addr)
                //case 0xF00000..<0xF80000:       //Phase read
                case:                           //Rest of memory
                    fmt.println(addr)
                    panic("Unused mem access")
            }
        } else {
            switch addr {
                /*case 0x000000..<0x080000:       //RAM
                case 0x400000..<0x420000:       //ROM
                case 0x900000..<0xA00000:       //SCC_R/Phase adjust
                case 0xB00000..<0xC00000:       //SCC_W/Phase adjust
                case 0xD00000..<0xE00000:       //IWM
                case 0xE80000..<0xF00000:       //VIA
                case 0xF00000..<0xF80000:       //Phase read*/
                case:                           //Rest of memory
                    fmt.println(addr)
                    panic("Unused mem access")
            }
        }
    }
}

bus_write :: proc(size: u8, address: u32, value: u32)
{
    addr := address & 0xFFFFFF
    when TEST_ENABLE {
        test_write(size, addr, value)
    } else {
        if via_get_overlay() {
            switch addr {
                /*case 0x000000..<0x080000:       //ROM
                case 0x400000..<0x420000:       //ROM*/
                case 0x600000..<0x680000:       //RAM
                    bus_write_ram(size, addr, value)
                /*case 0x900000..<0xA00000:       //SCC_R/Phase adjust
                case 0xB00000..<0xC00000:       //SCC_W/Phase adjust
                case 0xD00000..<0xE00000:       //IWM*/
                case 0xE80000..<0xF00000:       //VIA
                    via_write(size, addr, value)
                //case 0xF00000..<0xF80000:       //Phase read
                case:                           //Rest of memory
                    fmt.println(addr)
                    panic("Unused mem access")
            }
        } else {
            switch addr {
                /*case 0x000000..<0x080000:       //RAM
                case 0x400000..<0x420000:       //ROM
                case 0x900000..<0xA00000:       //SCC_R/Phase adjust
                case 0xB00000..<0xC00000:       //SCC_W/Phase adjust
                case 0xD00000..<0xE00000:       //IWM
                case 0xE80000..<0xF00000:       //VIA
                case 0xF00000..<0xF80000:       //Phase read*/
                case:                           //Rest of memory
                    fmt.println(addr)
                    panic("Unused mem access")
            }
        }
    }
}

bus_read_rom :: proc(size: u8, addr: u32) -> u32
{
    switch size {
        case 8:
            return u32(rom_mem[addr])
        case 16:
            return u32(rom_mem[addr + 1]) | (u32(rom_mem[addr]) << 8)
        case 32:
            return u32(rom_mem[addr + 3]) | (u32(rom_mem[addr + 2]) << 8) |
                (u32(rom_mem[addr + 1]) << 16) | (u32(rom_mem[addr]) << 24)
     }
     return 0
}

bus_read_ram :: proc(size: u8, addr: u32) -> u32
{
    switch size {
        case 8:
            return u32(ram_mem[addr])
        case 16:
            return u32(ram_mem[addr + 1]) | (u32(ram_mem[addr]) << 8)
        case 32:
            return u32(ram_mem[addr + 3]) | (u32(ram_mem[addr + 2]) << 8) |
                (u32(ram_mem[addr + 1]) << 16) | (u32(ram_mem[addr]) << 24)
     }
     return 0
}

bus_write_ram :: proc(size: u8, addr: u32, value: u32) -> u32
{
    switch size {
        case 8:
            ram_mem[addr] = u8(value)
        case 16:
            ram_mem[addr + 1] = u8(value & 0xFF)
            ram_mem[addr + 0] = u8((value >> 8) & 0xFF)
        case 32:
            ram_mem[addr + 3] = u8(value & 0xFF)
            ram_mem[addr + 2] = u8((value >> 8) & 0xFF)
            ram_mem[addr + 1] = u8((value >> 16) & 0xFF)
            ram_mem[addr + 0] = u8((value >> 24) & 0xFF)
     }
     return 0
}

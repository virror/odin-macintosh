package main

import "core:fmt"
import "core:os"

ram_mem: [0x1000000]u8
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
        addr += 0x400000
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

bus_write :: proc(size: u8, address: u32, value: u32)
{
    addr := address & 0xFFFFFF
    when TEST_ENABLE {
        test_write(size, addr, value)
    } else {
        addr += 0x400000
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

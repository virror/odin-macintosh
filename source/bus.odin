package main

import "core:fmt"
import "core:os"

@(private="file")
rom_mem: [0x20000]u8

bus_init :: proc()
{
    fmt.println("Bus init") //Get rid of unused fmt error
    file, err := os.open("roms/Macintosh 512K.ROM", os.O_RDONLY)
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
        if via_get_regA().overlay {
            switch addr {
                case 0x000000..<0x080000:       //ROM
                    return bus_read_rom(size, addr)
                case 0x400000..<0x420000:       //ROM
                    addr -= 0x400000
                    return bus_read_rom(size, addr)
                case 0x600000..<0x680000:       //RAM
                    addr -= 0x600000
                    return ram_read(size, addr)
                case 0x900000..<0xA00000:       //SCC_R/Phase adjust
                    if size == 8 {
                        return scc_read(addr)
                    } else {
                        fmt.println(addr)
                        return 0
                    }
                case 0xB00000..<0xC00000:       //SCC_W/Phase adjust
                    if size == 8 {
                        return scc_read(addr)
                    } else {
                        fmt.println(addr)
                        return 0
                    }
                case 0xD00000..<0xE00000:       //IWM
                    return iwm_read(size, addr)
                case 0xE80000..<0xF00000:       //VIA
                    return via_read(size, addr)
                case 0xF00000..<0xF80000:       //Phase read
                    return 0
                case 0xF80000..<0xF80010:       //Test stuff?
                    return 0
                case:                           //Rest of memory
                    fmt.println(addr)
                    panic("Unused mem access")
            }
        } else {
            switch addr {
                case 0x000000..<0x080000:       //RAM
                    return ram_read(size, addr)
                case 0x400000..<0x420000:       //ROM
                    addr -= 0x400000
                    return bus_read_rom(size, addr)
                case 0x900000..<0xA00000:       //SCC_R/Phase adjust
                    if size == 8 {
                        return scc_read(addr)
                    } else {
                        fmt.println(addr)
                        return 0
                    }
                case 0xB00000..<0xC00000:       //SCC_W/Phase adjust
                    if size == 8 {
                        return scc_read(addr)
                    } else {
                        fmt.println(addr)
                        return 0
                    }
                case 0xD00000..<0xE00000:       //IWM
                    return iwm_read(size, addr)
                case 0xE80000..<0xF00000:       //VIA
                    return via_read(size, addr)
                //case 0xF00000..<0xF80000:       //Phase read
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
        if via_get_regA().overlay {
            switch addr {
                /*case 0x000000..<0x080000:       //ROM
                case 0x400000..<0x420000:       //ROM*/
                case 0x600000..<0x680000:       //RAM
                    addr -= 0x600000
                    ram_write(size, addr, value)
                case 0x900000..<0xA00000:       //SCC_R/Phase adjust
                    if size == 8 {
                        scc_write(addr, value)
                    } else {
                        fmt.println(addr)
                    }
                case 0xB00000..<0xC00000:       //SCC_W/Phase adjust
                    if size == 8 {
                        scc_write(addr, value)
                    } else {
                        fmt.println(addr)
                    }
                case 0xD00000..<0xE00000:       //IWM
                    iwm_write(size, addr, value)
                case 0xE80000..<0xF00000:       //VIA
                    via_write(size, addr, value)
                //case 0xF00000..<0xF80000:       //Phase write
                case:                           //Rest of memory
                    fmt.println(addr)
                    panic("Unused mem access")
            }
        } else {
            switch addr {
                case 0x000000..<0x080000:       //RAM
                    ram_write(size, addr, value)
                case 0x400000..<0x420000:       //ROM
                    fmt.println("Read only memory?")
                case 0x900000..<0xA00000:       //SCC_R/Phase adjust
                    if size == 8 {
                        scc_write(addr, value)
                    } else {
                        fmt.println(addr)
                    }
                case 0xB00000..<0xC00000:       //SCC_W/Phase adjust
                    if size == 8 {
                        scc_write(addr, value)
                    } else {
                        fmt.println(addr)
                    }
                case 0xD00000..<0xE00000:       //IWM
                    iwm_write(size, addr, value)
                case 0xE80000..<0xF00000:       //VIA
                    via_write(size, addr, value)
                //case 0xF00000..<0xF80000:       //Phase write*/
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

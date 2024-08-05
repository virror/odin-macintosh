package main

//import "core:fmt"

when MAC_VER == .Mac_128 {
    RAM_SIZE :: 0x20000
    VRAM_ALT_START :: 0x12700
}
when MAC_VER == .Mac_512 {
    RAM_SIZE :: 0x80000
    VRAM_ALT_START :: 0x72700
}
when MAC_VER == .Mac_Plus {
    RAM_SIZE :: 0x400000
    VRAM_ALT_START :: 0x3F2700
}

VRAM_SIZE :: 0x5580
VRAM_DIFF :: 0x8000
VRAM_START :: VRAM_ALT_START + VRAM_DIFF
VRAM_END :: VRAM_START + VRAM_SIZE
VRAM_ALT_END :: VRAM_ALT_START + VRAM_SIZE


@(private="file")
ram_mem: [RAM_SIZE]u8

ram_read :: proc(size: u8, addr: u32) -> u32
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

ram_write :: proc(size: u8, addr: u32, value: u32) -> u32
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

ram_get_vram :: proc() -> []u8
{
    if !via_get_regA().page2 {   // Alt screen buffer
        return ram_mem[VRAM_ALT_START:VRAM_ALT_END]
    } else {                    // Main screen buffer
        return ram_mem[VRAM_START:VRAM_END]
    }
}
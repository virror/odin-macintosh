package main

@(private="file")
vram: [0x2AC00]u8
@(private="file")
counter: u32
@(private="file")
line: u32

//0.0638µs per pixel
//32.67µs per scanline
//12.25µs per hblank
//44.92µs per line
//1257.76 for whole vblank (28 lines)
gpu_step :: proc(cycles: u32) -> bool
{
    counter += cycles
    if counter >= 352 {
        line += 1
        via_set_h4(false)
        if line >= 370 {
            line = 0
        }
        counter -= 352

        if line == 342 { //Start vblank
            via_irq(.vBlank)
            return true
        } else if line >= 0 && line < 342 { //Draw line
            vid_ram := ram_get_vram()
            for i:u32=0; i<64; i+=1 {
                idx := line * 64 + i
                for j:u32=0; j<8; j+=1 {
                    vram[idx * 8 + j] = (1 - ((vid_ram[idx] >> (7 - j)) & 1)) * 255
                }
            }
        }
    } else if counter >= 96 {
        via_set_h4(true)
    }
    return false
}

gpu_draw :: proc()
{
    texture_create(WIN_WIDTH, WIN_HEIGHT, &vram[0])
    update()
}
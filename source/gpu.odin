package main

@(private="file")
vram: [0x2AC00]u8
@(private="file")
timer: u32

gpu_step :: proc(cycles: u32) -> bool
{
    timer += cycles
    if timer >= 277833 {
        timer = 0
        return true
    } else {
        return false
    }
}

gpu_draw :: proc()
{
    vid_ram := ram_get_vram()
    for i:u32=0; i<21888; i+=1 {
        for j:u32=0; j<8; j+=1 {
            vram[i*8+j] = (1 - ((vid_ram[i] >> (7-j)) & 1)) * 255
        }
    }
    texture_create(WIN_WIDTH, WIN_HEIGHT, &vram[0])
}
package main

@(private="file")
MTempY :: 0x0828
@(private="file")
MTempX :: 0x082A
@(private="file")
RawMouseY :: 0x082C
@(private="file")
RawMouseX :: 0x082E
@(private="file")
CrsrNew :: 0x08CE

input_mouse_update :: proc(xpos: i32, ypos: i32)
{
    if via_get_regA().overlay {
        return
    }
    ram_write(16, MTempX, u32(xpos))
    ram_write(16, RawMouseX, u32(xpos))
    ram_write(16, MTempY, u32(ypos))
    ram_write(16, RawMouseY, u32(ypos))
    ram_write(8, CrsrNew, 1)
}

input_mouse_button :: proc()
{
    via_mouse_btn()
}
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

input_mouse_update :: proc(xrel: i32, yrel: i32)
{
    mouse_x := i32(ram_read(16, RawMouseX))
    mouse_y := i32(ram_read(16, RawMouseY))

    mouse_x += xrel
    mouse_y += yrel

    ram_write(16, MTempX, u32(mouse_x))
    ram_write(16, RawMouseX, u32(mouse_x))
    ram_write(16, MTempY, u32(mouse_y))
    ram_write(16, RawMouseY, u32(mouse_y))
    ram_write(8, CrsrNew, 1)
}

input_mouse_button :: proc()
{
    via_mouse_btn()
}
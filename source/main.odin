package main

import "core:fmt"
import "core:strings"
import "core:os"
import sdl "vendor:sdl2"
import sdlttf "vendor:sdl2/ttf"

WIN_WIDTH :: 1024
WIN_HEIGHT :: 512

exit := false
@(private="file")
pause := true
@(private="file")
step := false
@(private="file")
window: ^sdl.Window
@(private="file")
ttyfile: os.Handle

main :: proc()
{
    sdl.Init(sdl.INIT_VIDEO)
    defer sdl.Quit()

    sdlttf.Init()
    defer sdlttf.Quit()

    window = sdl.CreateWindow("odin-macintosh", 100, 100, WIN_WIDTH, WIN_HEIGHT,
        sdl.WINDOW_OPENGL)
    assert(window != nil, "Failed to create main window")
    defer sdl.DestroyWindow(window)

    debug_window := sdl.CreateWindow("debug", 800, 100, 600, 600,
        sdl.WINDOW_OPENGL | sdl.WINDOW_RESIZABLE)
    assert(debug_window != nil, "Failed to create debug window")
    defer sdl.DestroyWindow(debug_window)

    render_init(window)

    debug_render := sdl.CreateRenderer(debug_window, -1, sdl.RENDERER_ACCELERATED)

    ticks: u64

    //Emu stuff
    debug_init(debug_render)
    bus_init()
    cpu_init()

    draw_debug_window(debug_render)
    render_screen()

    test_file()

    for !exit {
        ticks = 0

        if !pause || step {
            tick := cpu_step()

            if step {
                step = false
                draw_debug_window(debug_render)
                free_all(context.temp_allocator)
            }
        } else {
            handle_events()
        }
    }
    render_delete()
}

draw_debug_window :: proc(debug_render: ^sdl.Renderer)
{
    sdl.RenderClear(debug_render)
    debug_draw()
    sdl.RenderPresent(debug_render)
}

update :: proc()
{
    render_screen()
    handle_events()
}

@(private="file")
handle_events :: proc()
{
    event: sdl.Event
    for sdl.PollEvent(&event) {
        #partial switch event.type {
            case sdl.EventType.QUIT:
                exit = true
            case sdl.EventType.WINDOWEVENT:
                if event.window.event == sdl.WindowEventID.CLOSE {
                    exit = true
                }
            case:
                handle_dbg_keys(&event)
        }
    }
}

@(private="file")
handle_dbg_keys :: proc(event: ^sdl.Event)
{
    if event.type == sdl.EventType.KEYDOWN {
        #partial switch event.key.keysym.sym {
            case sdl.Keycode.p:
                pause = !pause
            case sdl.Keycode.s:
                step = true
            case sdl.Keycode.ESCAPE:
                exit = true
            case sdl.Keycode.TAB:
                debug_switch()
        }
    }
}

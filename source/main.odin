package main

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
@(private="file")
debug_render: ^sdl.Renderer

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

    debug_render = sdl.CreateRenderer(debug_window, -1, sdl.RENDERER_ACCELERATED)

    //Emu stuff
    debug_init(debug_render)
    via_init()
    bus_init()
    cpu_init()

    draw_debug_window()
    render_screen()

    when TEST_ENABLE {
        test_all()
    }

    for !exit {
        if !pause || step {
            cpu_step()

            if step {
                step = false
                draw_debug_window()
                free_all(context.temp_allocator)
            }
        } else {
            handle_events()
        }
    }
    render_delete()
}

draw_debug_window :: proc()
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

pause :: proc()
{
    pause = true
    draw_debug_window()
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

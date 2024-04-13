package main

import "core:fmt"
import sdl "vendor:sdl2"
import sdlttf "vendor:sdl2/ttf"

DebugType :: enum {
    cpu,
    //gpu,
    last,
}
@(private="file")
debug_type: DebugType

@(private="file")
renderer : ^sdl.Renderer
@(private="file")
font : ^sdlttf.Font

debug_init :: proc(renderera: ^sdl.Renderer)
{
    font = sdlttf.OpenFont("SpaceMono-Regular.ttf", 18)
    renderer = renderera
}

debug_draw :: proc()
{
    switch debug_type {
        case .cpu:
            debug_cpu_draw()
        /*case .gpu:
            debug_gpu_draw()*/
        case .last:
            //NA
    }
}

debug_switch :: proc()
{
    tmp := u32(debug_type)
    tmp += 1
    debug_type = DebugType(tmp)
    if debug_type == .last {
        debug_type = .cpu
    }
    draw_debug_window(renderer)
}

debug_text :: proc(text: cstring, posX: i32, posY: i32)
{
    surface := sdlttf.RenderText_Solid(font, text, {255, 255, 255, 255})
    texture := sdl.CreateTextureFromSurface(renderer, surface)

    texW : i32 = 0
    texH : i32 = 0
    sdl.QueryTexture(texture, nil, nil, &texW, &texH)

    text_rect: sdl.Rect
    text_rect.x = posX
    text_rect.y = posY
    text_rect.w = texW
    text_rect.h = texH

    sdl.RenderCopy(renderer, texture, nil, &text_rect)

    sdl.FreeSurface(surface)
    sdl.DestroyTexture(texture)
}

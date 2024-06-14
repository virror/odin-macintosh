package main

import "core:fmt"

@(private="file")
last_op : string

debug_cpu_draw :: proc()
{
    debug_text(fmt.caprintf("PC 0x%8x", pc), 10, 10)
    debug_text(fmt.caprintf("D0 0x%8x", D[0]), 10, 35)
    debug_text(fmt.caprintf("A0 0x%8x", A[0]), 240, 35)
    debug_text(fmt.caprintf("D1 0x%8x", D[1]), 10, 60)
    debug_text(fmt.caprintf("A1 0x%8x", A[1]), 240, 60)
    debug_text(fmt.caprintf("D2 0x%8x", D[2]), 10, 85)
    debug_text(fmt.caprintf("A2 0x%8x", A[2]), 240, 85)
    debug_text(fmt.caprintf("D3 0x%8x", D[3]), 10, 110)
    debug_text(fmt.caprintf("A3 0x%8x", A[3]), 240, 110)
    debug_text(fmt.caprintf("D4 0x%8x", D[4]), 10, 135)
    debug_text(fmt.caprintf("A4 0x%8x", A[4]), 240, 135)
    debug_text(fmt.caprintf("D5 0x%8x", D[5]), 10, 160)
    debug_text(fmt.caprintf("A5 0x%8x", A[5]), 240, 160)
    debug_text(fmt.caprintf("D6 0x%8x", D[6]), 10, 185)
    debug_text(fmt.caprintf("A6 0x%8x", A[6]), 240, 185)
    debug_text(fmt.caprintf("D7 0x%8x", D[7]), 10, 210)
    debug_text(fmt.caprintf("A7 0x%8x", cpu_Areg_get(7)), 240, 210)

    debug_text(fmt.caprintf("SR %8b", u16(sr)), 10, 260)

    debug_text(fmt.caprintf("> %s", instrTbl[prefetch[0]].debug), 20, 300)
}

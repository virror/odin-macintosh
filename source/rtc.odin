package main

import "core:fmt"
import "core:os"

@(private="file")
rtc_data_cnt: u8
@(private="file")
rtc_data: u8
@(private="file")
rtc_command: u8
@(private="file")
rtc_r_w: bool
@(private="file")
rtc_ram: [20]u8
@(private="file")
rtc_protect: bool
@(private="file")
rtc_seconds: u32
@(private="file")
sec1_tmr: u32

rtc_init :: proc()
{
    rtc_load()
}

rtc_run :: proc(value: u8)
{
    if ((value >> 2) & 1) == 0 {    //Clock enable
        if ((value >> 1) & 1) == 1 {    //Clock high
            if rtc_command != 0 && rtc_r_w == false {
                rtc_read()
            } else {
                rtc_data |= (value & 1)
                rtc_data_cnt += 1
                if rtc_data_cnt == 8 {
                    if rtc_command == 0 {
                        rtc_command = rtc_data
                        rtc_r_w = ((rtc_command & 0x80) == 0)
                    } else if rtc_r_w {
                        rtc_write()
                    }
                    rtc_data_cnt = 0
                    rtc_data = 0
                } else {
                    rtc_data = rtc_data << 1
                }
            }
        }
    } else {
        rtc_data_cnt = 0
        rtc_data = 0
    }
}

@(private="file")
rtc_read :: proc()
{
    rtc_data_cnt += 1
    if rtc_data_cnt == 1 {
        cmd := rtc_command >> 2
        switch (cmd) {
            case 32, 36:
                rtc_data = u8(rtc_seconds)
            case 33, 37:
                rtc_data = u8(rtc_seconds >> 8)
            case 34, 38:
                rtc_data = u8(rtc_seconds >> 16)
            case 35, 39:
                rtc_data = u8(rtc_seconds >> 24)
            case 40..=43:
                addr := cmd & 3
                rtc_data = rtc_ram[addr]
            case 48..=63:
                addr := cmd & 15
                rtc_data = rtc_ram[addr]
            case:
                fmt.println("Unknown RTC read command")
        }
    }
    via_set_TCdata((rtc_data & 0x80) > 0)
    if rtc_data_cnt == 8 {
        rtc_command = 0
        rtc_data_cnt = 0
        rtc_data = 0
    } else {
        rtc_data = rtc_data << 1
    }
}

@(private="file")
rtc_write :: proc()
{
    cmd := rtc_command >> 2
    switch (cmd) {
        case 0, 4:
            rtc_seconds &= 0xFFFFFF00
            rtc_seconds |= u32(rtc_data)
        case 1, 5:
            rtc_seconds &= 0xFFFF00FF
            rtc_seconds |= u32(rtc_data) << 8
        case 2, 6:
            rtc_seconds &= 0xFF00FFFF
            rtc_seconds |= u32(rtc_data) << 16
        case 3, 7:
            rtc_seconds &= 0x00FFFFFF
            rtc_seconds |= u32(rtc_data) << 24
        case 12:
            //Ignore command
        case 13:
            rtc_protect = ((rtc_data & 0x80) > 0)
        case 8..=11:
            addr := cmd & 3
            rtc_ram[addr] = rtc_data
        case 16..=31:
            addr := cmd & 15
            rtc_ram[addr] = rtc_data
        case:
            fmt.println("Unknown RTC write command")
    }
    rtc_command = 0
}

@(private="file")
rtc_save :: proc()
{
    file, err := os.open("rtc.sav", os.O_WRONLY | os.O_CREATE)
    assert(err == 0, "Failed to open rtc.sav")
    _, err2 := os.write(file, rtc_ram[0:20])
    assert(err2 == 0, "Failed to read rtc data")
    os.close(file)
}

@(private="file")
rtc_load :: proc()
{
    file, err := os.open("rtc.sav", os.O_RDONLY)
    assert(err == 0, "Failed to open rtc.sav")
    _, err2 := os.read(file, rtc_ram[0:20])
    assert(err2 == 0, "Failed to read rtc data")
    os.close(file)
}

rtc_update_1sec :: proc(cycles: u32)
{
    sec1_tmr += cycles
    if sec1_tmr > 783360 {
        sec1_tmr -= 783360
        via_irq(.oneSec)
        rtc_seconds += 1
    }
}

package main

import "core:fmt"
import "core:os"
import "core:encoding/json"

TEST_ENABLE :: false
TEST_ALL :: true
TEST_FILE :: "tests/SUB.l.json"
TEST_BREAK_ERROR :: false

@(private="file")
Registers :: struct {
    d0: u32,
    d1: u32,
    d2: u32,
    d3: u32,
    d4: u32,
    d5: u32,
    d6: u32,
    d7: u32,
    a0: u32,
    a1: u32,
    a2: u32,
    a3: u32,
    a4: u32,
    a5: u32,
    a6: u32,
    usp: u32,
    ssp: u32,
    sr: u16,
    pc: u32,
    prefetch: [2]u16,
    ram: [dynamic][2]u32,
}

@(private="file")
Json_data :: struct {
    name: string,
    initial: Registers,
    final: Registers,
    length: u32,
    transactions: [][]union{ string, int },
}

@(private="file")
test_fail: bool
@(private="file")
fail_cnt: int
@(private="file")
ram_mem: [0x1000000]u8

test_all :: proc()
{
    when TEST_ALL {
        fd: os.Handle
        err: os.Errno
        info: []os.File_Info
        fd, err = os.open("tests")
        info, err = os.read_dir(fd, -1)
        length := len(info)
        for i := 0; i < length; i += 1 {
            test_fail = false
            fail_cnt = 0
            fmt.println(info[i].fullpath)
            test_file(info[i].fullpath)
            if test_fail == true {
                break
            }
        }
    } else {
        fmt.println(TEST_FILE)
        test_file(TEST_FILE)
    }
}

test_file :: proc(filename: string)
{
    //Setup
    data, err := os.read_entire_file_from_filename(filename)
    assert(err == true, "Could not load test file")
    json_data: [dynamic]Json_data
    error := json.unmarshal(data, &json_data)
    if error != nil {
        fmt.println(error)
        return
    }
    delete(data)
    test_length := len(json_data)
    for i:= 0; i < test_length; i += 1 {
        if !test_fail {
            test_run(json_data[i])
        }
    }
    fmt.printf("Failed: %d\n", fail_cnt)
}

@(private="file")
test_run :: proc(json_data: Json_data)
{
    error_string: string
    D[0] = json_data.initial.d0
    D[1] = json_data.initial.d1
    D[2] = json_data.initial.d2
    D[3] = json_data.initial.d3
    D[4] = json_data.initial.d4
    D[5] = json_data.initial.d5
    D[6] = json_data.initial.d6
    D[7] = json_data.initial.d7
    A[0] = json_data.initial.a0
    A[1] = json_data.initial.a1
    A[2] = json_data.initial.a2
    A[3] = json_data.initial.a3
    A[4] = json_data.initial.a4
    A[5] = json_data.initial.a5
    A[6] = json_data.initial.a6
    usp = json_data.initial.usp
    ssp = json_data.initial.ssp
    sr = SR(json_data.initial.sr)
    pc = json_data.initial.pc

    bus_write(16, pc, u32(json_data.initial.prefetch[0]))
    bus_write(16, pc + 2, u32(json_data.initial.prefetch[1]))
    prefetch[0] = json_data.initial.prefetch[0]
    prefetch[2] = json_data.initial.prefetch[1]

    ram_length := len(json_data.initial.ram)
    for i:= 0; i < ram_length; i += 1 {
        mem_val := json_data.initial.ram[i]
        bus_write(8, mem_val[0], u32(mem_val[1]))
    }

    //Run opcode
    cycles := cpu_decode(prefetch[0])

    //Compare results
    if D[0] != json_data.final.d0 {
        error_string = fmt.aprintf("Fail: D0 %d != %d", D[0], json_data.final.d0)
    }
    if D[1] != json_data.final.d1 {
        error_string = fmt.aprintf("Fail: D1 %d != %d", D[1], json_data.final.d1)
    }
    if D[2] != json_data.final.d2 {
        error_string = fmt.aprintf("Fail: D2 %d != %d", D[2], json_data.final.d2)
    }
    if D[3] != json_data.final.d3 {
        error_string = fmt.aprintf("Fail: D3 %d != %d", D[3], json_data.final.d3)
    }
    if D[4] != json_data.final.d4 {
        error_string = fmt.aprintf("Fail: D4 %d != %d", D[4], json_data.final.d4)
    }
    if D[5] != json_data.final.d5 {
        error_string = fmt.aprintf("Fail: D5 %d != %d", D[5], json_data.final.d5)
    }
    if D[6] != json_data.final.d6 {
        error_string = fmt.aprintf("Fail: D6 %d != %d", D[6], json_data.final.d6)
    }
    if D[7] != json_data.final.d7 {
        error_string = fmt.aprintf("Fail: D7 %d != %d", D[7], json_data.final.d7)
    }
    if A[0] != json_data.final.a0 {
        error_string = fmt.aprintf("Fail: A0 %d != %d", A[0], json_data.final.a0)
    }
    if A[1] != json_data.final.a1 {
        error_string = fmt.aprintf("Fail: A1 %d != %d", A[1], json_data.final.a1)
    }
    if A[2] != json_data.final.a2 {
        error_string = fmt.aprintf("Fail: A2 %d != %d", A[2], json_data.final.a2)
    }
    if A[3] != json_data.final.a3 {
        error_string = fmt.aprintf("Fail: A3 %d != %d", A[3], json_data.final.a3)
    }
    if A[4] != json_data.final.a4 {
        error_string = fmt.aprintf("Fail: A4 %d != %d", A[4], json_data.final.a4)
    }
    if A[5] != json_data.final.a5 {
        error_string = fmt.aprintf("Fail: A5 %d != %d", A[5], json_data.final.a5)
    }
    if A[6] != json_data.final.a6 {
        error_string = fmt.aprintf("Fail: A6 %d != %d", A[6], json_data.final.a6)
    }
    if usp != json_data.final.usp {
        error_string = fmt.aprintf("Fail: usp %d != %d", usp, json_data.final.usp)
    }
    if ssp != json_data.final.ssp {
        error_string = fmt.aprintf("Fail: ssp %d != %d", ssp, json_data.final.ssp)
    }
    if u16(sr) != json_data.final.sr {
        error_string = fmt.aprintf("Fail: sr %d != %d", u16(sr), json_data.final.sr)
    }
    if prefetch[0] != json_data.final.prefetch[0] {
        error_string = fmt.aprintf("Fail: prefetch 0 %d != %d", prefetch[0], json_data.final.prefetch[0])
    }
    if prefetch[2] != json_data.final.prefetch[1] {
        error_string = fmt.aprintf("Fail: prefetch 1 %d != %d", prefetch[2], json_data.final.prefetch[1])
    }
    if pc != json_data.final.pc {
        error_string = fmt.aprintf("Fail: pc %d != %d", pc, json_data.final.pc)
    }
    final_ram_length := len(json_data.final.ram)
    for i:= 0; i < final_ram_length; i += 1 {
        final := json_data.final.ram[i]
        data := u8(bus_read(8, final[0]))
        if u32(data) != final[1] {
            error_string = fmt.aprintf("Fail: ram at %d: %d != %d", final[0], data, final[1])
        }
    }
    if cycles != json_data.length {
        error_string = fmt.aprintf("Fail: cycles %d != %d", cycles, json_data.length)
    }
    /*transaction_len := len(json_data.transactions)
    for i:= 0; i < transaction_len; i += 1 {
        type := json_data.transactions[i][0]

        if cpu_trans[i][0] != type {
            fmt.printfln("Fail: transaction %d, 0: %s != %s", i, cpu_trans[i][0], type)
            error_string = "a"
        }
        if cpu_trans[i][1] != json_data.transactions[i][1] {
            fmt.printfln("Fail: transaction %d, 1: %d != %d", i, cpu_trans[i][1], json_data.transactions[i][1])
            error_string = "a"
        }
        if type != "n" {
            /*if cpu_trans[i][2] != json_data.transactions[i][2] {
                fmt.printfln("Fail: transaction %d, 2: %d != %d", i, cpu_trans[i][2], json_data.transactions[i][2])
            }*/
            if cpu_trans[i][3] != json_data.transactions[i][3] {
                fmt.printfln("Fail: transaction %d, 3: %d != %d", i, cpu_trans[i][3], json_data.transactions[i][3])
                error_string = "a"
            }
            if cpu_trans[i][4] != json_data.transactions[i][4] {
                fmt.printfln("Fail: transaction %d, 4: %s != %s", i, cpu_trans[i][4], json_data.transactions[i][4])
                error_string = "a"
            }
            if cpu_trans[i][5] != json_data.transactions[i][5] {
                fmt.printfln("Fail: transaction %d, 5: %d != %d", i, cpu_trans[i][5], json_data.transactions[i][5])
                error_string = "a"//fmt.aprintf("Fail: transaction %d, 5: %d != %d", i, cpu_trans[i][5], json_data.transactions[i][5])
            }
        }
    }*/
    if error_string != "" {
        when TEST_BREAK_ERROR {
            fmt.println(json_data.name)
            fmt.println(error_string)
            test_fail = true
            exit = true
        }
        fail_cnt += 1
    }
    exit = true
}

test_read :: proc(size: u8, addr: u32) -> u32
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

test_write :: proc(size: u8, addr: u32, value: u32)
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
}

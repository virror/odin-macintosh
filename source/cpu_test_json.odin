package main

import "core:fmt"
import "core:os"
import "core:encoding/json"

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
}

@(private="file")
test_fail: bool

test_file :: proc()
{
    //Setup
    data, err := os.read_entire_file_from_filename("tests/ADD.b.json")
    assert(err == true)
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
    A[7] = json_data.initial.ssp
    sr = json_data.initial.sr
    pc = json_data.initial.pc

    bus_write16(pc, json_data.initial.prefetch[0])
    bus_write16(pc + 2, json_data.initial.prefetch[1])

    ram_length := len(json_data.initial.ram)
    for i:= 0; i < ram_length; i += 1 {
        mem_val := json_data.initial.ram[i]
        bus_write8(mem_val[0], u8(mem_val[1]))
    }

    //Run opcode
    opcode := bus_read16(pc)
    pc += 2
    cpu_decode(opcode)

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
    if A[7] != json_data.final.ssp {
        error_string = fmt.aprintf("Fail: ssp %d != %d", A[7], json_data.final.ssp)
    }
    //TODO: Test sr
    /*if sr != json_data.final.sr {
        error_string = fmt.aprintf("Fail: sr %d != %d", sr, json_data.final.sr)
    }*/
    //TODO: Test prefetch
    if pc != json_data.final.pc {
        error_string = fmt.aprintf("Fail: pc %d != %d", pc, json_data.final.pc)
    }
    for i:= 0; i < ram_length; i += 1 {
        final := json_data.final.ram[i]
        data := bus_read8(final[0])
        if u32(data) != final[1] {
            error_string = fmt.aprintf("Fail: ram %d != %d", data, final[1])
        }
    }
    //TODO: Test length
    if error_string != "" {
        fmt.println(json_data.name)
        fmt.println(error_string)
        test_fail = true
        exit = true
    }
}
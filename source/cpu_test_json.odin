package main

import "core:fmt"
import "core:os"
import "core:encoding/json"

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
    a7: u32,
    usp: u32,
    ssp: u32,
    sr: u16,
    pc: u32,
    prefetch: [2]u16,
    ram: [dynamic][2]u32,
}

Json_data :: struct {
    name: string,
    initial: Registers,
    final: Registers,
    length: u32,
}

test_file :: proc()
{
    //Setup
    data, err := os.read_entire_file_from_filename("tests/ADD.b.json")
    assert(err == true)
    json_data: Json_data
    error := json.unmarshal(data, &json_data)
    if error != nil {
        fmt.println("error")
    }
    delete(data)

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
    A[7] = json_data.initial.a7
    usp = json_data.initial.usp
    ssp = json_data.initial.ssp
    sr = json_data.initial.sr
    pc = json_data.initial.pc

    bus_write16(pc, json_data.initial.prefetch[0])
    bus_write16(pc + 2, json_data.initial.prefetch[1])

    ram_length := len(json_data.initial.ram)
    for i:= 0; i < ram_length; i += 1 {
        mem_val := json_data.initial.ram[i]
        bus_write16(mem_val[0], u16(mem_val[1]))
    }

    //Run opcode
    fmt.println(json_data.name)
    cpu_decode(bus_read16(pc))
    pc += 2

    //Compare results
    if D[0] != json_data.final.d0 {
        fmt.printf("Fail: D0 %d != %d\n", D[0], json_data.final.d0)
    }
    if D[1] != json_data.final.d1 {
        fmt.printf("Fail: D1 %d != %d\n", D[1], json_data.final.d1)
    }
    if D[2] != json_data.final.d2 {
        fmt.printf("Fail: D2 %d != %d\n", D[2], json_data.final.d2)
    }
    if D[3] != json_data.final.d3 {
        fmt.printf("Fail: D3 %d != %d\n", D[3], json_data.final.d3)
    }
    if D[4] != json_data.final.d4 {
        fmt.printf("Fail: D4 %d != %d\n", D[4], json_data.final.d4)
    }
    if D[5] != json_data.final.d5 {
        fmt.printf("Fail: D5 %d != %d\n", D[5], json_data.final.d5)
    }
    if D[6] != json_data.final.d6 {
        fmt.printf("Fail: D6 %d != %d\n", D[6], json_data.final.d6)
    }
    if D[7] != json_data.final.d7 {
        fmt.printf("Fail: D7 %d != %d\n", D[7], json_data.final.d7)
    }
    if A[0] != json_data.final.a0 {
        fmt.printf("Fail: A0 %d != %d\n", A[0], json_data.final.a0)
    }
    if A[1] != json_data.final.a1 {
        fmt.printf("Fail: A1 %d != %d\n", A[1], json_data.final.a1)
    }
    if A[2] != json_data.final.a2 {
        fmt.printf("Fail: A2 %d != %d\n", A[2], json_data.final.a2)
    }
    if A[3] != json_data.final.a3 {
        fmt.printf("Fail: A3 %d != %d\n", A[3], json_data.final.a3)
    }
    if A[4] != json_data.final.a4 {
        fmt.printf("Fail: A4 %d != %d\n", A[4], json_data.final.a4)
    }
    if A[5] != json_data.final.a5 {
        fmt.printf("Fail: A5 %d != %d\n", A[5], json_data.final.a5)
    }
    if A[6] != json_data.final.a6 {
        fmt.printf("Fail: A6 %d != %d\n", A[6], json_data.final.a6)
    }
    if A[7] != json_data.final.a7 {
        fmt.printf("Fail: A7 %d != %d\n", A[7], json_data.final.a7)
    }
    if usp != json_data.final.usp {
        fmt.printf("Fail: usp %d != %d\n", usp, json_data.final.usp)
    }
    if ssp != json_data.final.ssp {
        fmt.printf("Fail: ssp %d != %d\n", ssp, json_data.final.ssp)
    }
    if sr != json_data.final.sr {
        fmt.printf("Fail: sr %d != %d\n", sr, json_data.final.sr)
    }
    if pc != json_data.final.pc {
        fmt.printf("Fail: pc %d != %d\n", pc, json_data.final.pc)
    }
    for i:= 0; i < ram_length; i += 1 {
        final := json_data.final.ram[i]
        data := bus_read16(final[0])
        if data != u16(final[1]) {
            fmt.printf("Fail: ram %d != %d\n", data, final[1])
        }
    }
}
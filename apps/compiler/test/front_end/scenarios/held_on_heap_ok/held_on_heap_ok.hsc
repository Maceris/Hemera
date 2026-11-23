package held_on_heap_ok

import compiler from "base:compiler"

/*
 * Structs that hold themselves, or each other, on the heap: checking a struct's fields for #owned and #scoped ones
 * reaches them through dynamic arrays and unions, and mustn't go round forever, nor into one whose body another
 * thread is still making. None of this is reported.
 */

// Itself, through a dynamic array
Node :: struct {
    name : string,
    kids : Node[..],
}

// Each other
Folder :: struct {
    files : File[..],
}

File :: struct {
    name : string,
    parents : Folder[..],
}

// Through a union's payload
Value :: union {
    Number(f64),
    List(Item[..]),
    Empty,
}

Item :: struct {
    key : string,
    value : Value,
}

// A body that's slow to make, with many fields, while what holds it on the heap is checked
fields :: fn() -> compiler.Code {
    spin := 0
    for i in 0..<200000 {
        spin = (spin + i) % 7
    }
    return if spin >= 0 {
        #code fields {
            a0 : int, a1 : int, a2 : int, a3 : int, a4 : int, a5 : int, a6 : int, a7 : int,
            b0 : int, b1 : int, b2 : int, b3 : int, b4 : int, b5 : int, b6 : int, b7 : int,
            c0 : int, c1 : int, c2 : int, c3 : int, c4 : int, c5 : int, c6 : int, c7 : int,
            d0 : int, d1 : int, d2 : int, d3 : int, d4 : int, d5 : int, d6 : int, d7 : int,
            back : Slow[..],
        }
    } else { #code fields {} }
}

Slow :: struct {
    #insert fields(),
}

HoldsSlow1 :: struct { all : Slow[..] }
HoldsSlow2 :: struct { all : Slow[..] }
HoldsSlow3 :: struct { all : Slow[..] }
HoldsSlow4 :: struct { all : Slow[..] }

/*
 * Owners that hold each other on the heap, each saying so: checked once every type is complete, without either
 * waiting for the other
 */
Drive :: struct #owned(eject) {
    volumes : Volume[..],
}

Volume :: struct #owned(unmount) {
    drives : Drive[..],
}

eject :: fn(drive: Drive) {
    compiler.forget(drive)
}

unmount :: fn(volume: Volume) {
    compiler.forget(volume)
}

// Would hand its value to another thread
send :: fn(value #crosses_threads : any) {
}

show :: fn(value: any) {
}

/*
 * What these reach, round Folder and File, Item and Value, and into Slow, is waited for before it's checked for
 * #thread_bound and secret parts, and none is
 */
share :: fn(folder: ptr[Folder], item: ptr[Item], holders: ptr[HoldsSlow2]) {
    send(folder)
    send(item)
    send(holders)
    show(folder)
    show(holders)
}

main :: fn() {
    node : Node
    folder : Folder
    item : Item
    slow : Slow
    holders : HoldsSlow1
}

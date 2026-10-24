package rawptr_read_only

zero :: fn(target: mut rawptr) {}

// A rawptr only reads what it points to; mut rawptr can change it
pass :: fn(target: rawptr) {
    zero(target)
}

main :: fn() -> int {
    x := 1
    pass(&x)
    return 0
}

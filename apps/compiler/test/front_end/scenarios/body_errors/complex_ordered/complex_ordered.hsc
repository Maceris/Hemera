package complex_ordered

// Complex numbers have no order, only == and != (docs/types.md, Complex Numbers and Quaternions)
main :: fn() -> bool {
    a : c64 = 1 + 2i
    b : c64 = 2 + 1i
    return a < b
}

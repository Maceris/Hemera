package stack_unrestricted

// An #unrestricted struct never points into the stack
Handle :: struct #unrestricted { data : ptr[int] }

main :: fn() {
    x := 5
    handle := Handle.{ data = &x }
}

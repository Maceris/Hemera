package valid_scenarios

dereference :: fn(p: ptr[mut int], q: ptr[int], s: ptr[Foo], array: ptr[int][3]) {
    p^ = 2
    p^ = q^
    value :: q^
    name :: s^.name
    member :: s.inner^
    element :: array[1]^
    total :: p^ + q^ * 2
}

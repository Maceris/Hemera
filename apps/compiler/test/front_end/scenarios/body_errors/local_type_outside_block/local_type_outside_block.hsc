package local_type_outside_block

// A type declared in a block is seen only there
main :: fn() -> int {
    if true {
        Inner :: struct {
            x : int,
        }
    }
    value := Inner.{x = 1}
    return value.x
}

package stack_pointer_to_holder

// holder holds a view of the stack, and Holder isn't #scoped, so a pointer to it would be shallow
Holder :: struct { values : int[] }

use_holder_pointer :: fn(holder: ptr[Holder]) {}

main :: fn() {
    buffer : int[16]
    holder := Holder.{ values = buffer }
    use_holder_pointer(&holder)
}

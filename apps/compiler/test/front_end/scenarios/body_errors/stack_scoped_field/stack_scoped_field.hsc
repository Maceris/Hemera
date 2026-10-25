package stack_scoped_field

// A #scoped struct can only be held by another #scoped one, since an ordinary struct can go on the heap
Parser :: struct #scoped { input : u8[] }

Holder :: struct {
    parser : Parser,
}

main :: fn() {
    holder : Holder
}

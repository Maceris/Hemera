package mut_view_pointer_read_only

// A ptr[(mut u8[])] changes the view's elements, but not the view itself
shorten :: fn(view: ptr[(mut u8[])]) {
    view^ = view^
}

main :: fn() {}

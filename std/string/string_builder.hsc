package string

append_chars :: fn(builder: ptr[mut StringBuilder], s: ptr[char], length: usize) {
    todo()
}

append_substring :: fn(builder: ptr[mut StringBuilder], s: string, start: usize, length: usize) {
    todo()
}

append :: fn(builder: ptr[mut StringBuilder], s: string) {
    todo()
}

append_char :: fn(builder: ptr[mut StringBuilder], s: char) {
    todo()
}

builder_to_string :: fn(builder: ptr[StringBuilder], allocator := context.allocator) -> string {
    todo()
}

free_buffer :: fn(builder: ptr[mut StringBuilder]) {
    todo()
}

init_string_builder :: fn(builder: ptr[mut StringBuilder], buffer_size := -1) {
    todo()
}

StringBuilder :: struct {
    data: ptr[char],
    capacity: usize,
    size: usize,
}

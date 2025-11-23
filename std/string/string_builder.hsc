package string_builder

append :: fn(builder: ptr[mut StringBuilder], s: ptr[char], length: u64) {
    //TODO(ches) implement this
}

append :: fn(builder: ptr[mut StringBuilder], s: string, start: u64, length: u64) {
    //TODO(ches) implement this
}

append :: fn(builder: ptr[mut StringBuilder], s: string) {
    //TODO(ches) implement this
}

append :: fn(builder: ptr[mut StringBuilder], s: char) {
    //TODO(ches) implement this
}

builder_to_string :: fn(builder: ptr[StringBuilder], allocator := context.allocator) -> string {
    //TODO(ches) implement this
}

free_buffer :: fn(builder: ptr[mut StringBuilder]) {
    //TODO(ches) implement this
}

init_string_builder :: fn(builder: ptr[mut StringBuilder], buffer_size := -1) {
    //TODO(ches) implement this
}

StringBuilder :: struct {
    data: ptr[char],
    capacity: u64,
    size: u64,
}

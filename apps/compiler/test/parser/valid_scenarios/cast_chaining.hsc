package valid_scenarios

// Casts chain like any other value, without wrapping them in parentheses
cast_chaining :: fn(data: rawptr, callback: rawptr) {
    info :: cast[ptr[TypeInfoStruct]](data).members
    byte :: cast[ptr[u8]](data)^
    third :: cast[ptr[Foo]](data).items[2].name
    result :: cast[fn(int) -> int](callback)(1)
    cast[ptr[mut int]](data)^ = 4
    if cast[ptr[TypeInfoString]](data).is_raw {
        return void
    }
    flag :: !cast[ptr[bool]](data)^
    sum :: cast[ptr[int]](data)^ + cast[ptr[int]](data)^
    // And the address of what a cast reaches
    field :: &cast[ptr[mut Foo]](data).count
    element :: &bit_cast[ptr[mut Foo]](data).items[2]
}

package link_name_alone

// #link_name only renames a #foreign function's symbol
helper #link_name("other") :: fn() -> u32 {
    return 0
}

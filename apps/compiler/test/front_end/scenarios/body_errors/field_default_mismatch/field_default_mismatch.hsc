package field_default_mismatch

// A string can't be an int field's default (docs/types.md, Structs)
Config :: struct {
    count : int = "seven",
}

main :: fn() -> int {
    config := Config.{}
    return config.count
}

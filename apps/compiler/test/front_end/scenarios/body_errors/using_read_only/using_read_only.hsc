package using_read_only

Config :: struct {
    width : int,
}

// Reads through it, so what it reaches can't be changed
View :: struct {
    using config : ptr[Config],
}

main :: fn() {
    config : Config
    view := View.{config = &config}
    view.width = 3
}

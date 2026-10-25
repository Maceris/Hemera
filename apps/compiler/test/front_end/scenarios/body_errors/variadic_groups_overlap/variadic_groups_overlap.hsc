package variadic_groups_overlap

// numbers may be given nothing, so a string after names could be either's
groups :: fn(names: string..., numbers: int..., more: string...) {}

main :: fn() {
    groups("a")
}

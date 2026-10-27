package match_on_cstring

// A cstring doesn't know its length, so match doesn't go through one; a string viewed from it does
kind :: fn(name: cstring) -> int {
    return match name {
        case "hi" => 1
        case _ => 2
    }
}

main :: fn() {
    _ = kind("hi")
}

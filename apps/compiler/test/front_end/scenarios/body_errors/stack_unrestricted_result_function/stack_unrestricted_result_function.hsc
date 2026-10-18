package stack_unrestricted_result_function

// A function whose result may point at its arguments can't be used where callers expect it can't
Fresh :: fn(text: string) -> (copy #unrestricted : string, ok : bool)
Borrowed :: fn(text: string) -> (copy : string, ok : bool)

fresh : Fresh : fn(text: string) -> (copy #unrestricted : string, ok : bool) {
    return "copy", true
}
borrowed : Borrowed : fn(text: string) -> (copy : string, ok : bool) {
    return text, true
}

main :: fn() {
    // Allowed: one whose result is unrestricted, where it may not be
    allowed : Borrowed = fresh
    not_allowed : Fresh = borrowed
}

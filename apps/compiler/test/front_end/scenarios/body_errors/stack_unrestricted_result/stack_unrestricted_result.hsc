package stack_unrestricted_result

// An #unrestricted result can't be what the function was given, which may be on the caller's stack
first_word :: fn(text: string) -> (word #unrestricted : string, found : bool) {
    return text, true
}

main :: fn() {
    word, found :: first_word("hello")
}

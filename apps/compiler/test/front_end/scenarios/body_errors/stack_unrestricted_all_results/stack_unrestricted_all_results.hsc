package stack_unrestricted_all_results

// #unrestricted after the results marks every one: a Result can't hold what the function was given
first_word :: fn(text: string) -> Result[string, int] #unrestricted {
    return .Ok(text)
}

main :: fn() {
    _ = first_word("hello")
}

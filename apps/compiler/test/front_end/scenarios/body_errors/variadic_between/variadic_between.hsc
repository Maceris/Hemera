package variadic_between

// The one between two groups can not be taken for the variadic one after it
around :: fn(numbers: int..., flag: bool, flags: bool...) {}

main :: fn() {
    around(1, true)
}

package variadic_default_positional

// A parameter with a default after a variadic one is only given by name
scaled :: fn(numbers: int..., scale: f32 = 1) {}

main :: fn() {
    scaled(1, 2.5)
}

package variadic_then_float

// An untyped 3 could be an int or the f32, so bar(false, 1, 2, 3) could not say where some_numbers end
bar :: fn(fiz: bool, some_numbers: int..., fuzz: f32) {}

main :: fn() {}

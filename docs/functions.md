# Functions

Functions are defined using `fn`. Below is a function named `say_hello` that takes no input, returns no output, which will print "hello" when called.

```
say_hello :: fn() {
    println("hello")
}
```

Inputs to functions can be provided in the parenthesis.

```
// text is a parameter, with a type of string
print_something :: fn(text: string) {
    println(text)
}

// Default values can be provided for parameters
print_something2 :: fn(text: string = "hello") {
    println(text)
}
```

Outputs from functions are provided using `->` followed by the type(s) that are returned.

```
get_one_number :: fn() -> int {
    return 4
}

get_two_numbers :: fn() -> int, int {
    return 2, 3
}

get_coordinates :: fn() -> x, y: int {
    // Outputs act like variables in scope
    x = 4
    y = 5
    return x, y
}

is_even :: fn(x: int) -> result: bool, mod: int {
    mod = x % 2
    result = mod == 0
    return // allowed, but not encouraged, if all results are assigned
}
```

Note that the `::` is actually 2 operators, a type could be provided instead of deduced, but that's usually quite redundant.
Below is an example that defines a type which might communicate more intent.

```
BinaryIntFunc :: alias fn(int, int) -> int

add_numbers : BinaryIntFunc : fn(x, y : int) -> int {
    return x + y
}
```

## Nesting Functions

```
main :: fn() {
    // Functions can be defined inside functions
    multiply :: fn(x, y: int) -> int {
        return x * y
    }

    a : int = 2
    b : int = 3

    // They are not different than top level functions
    c := multiply(a, b)
}
```

## First Class Functions

Functions are first class objects, and can be passed around just like any other type.

```
add :: fn(x, y: int) -> int {
    return x + y
}

main :: fn() {
    a : int = 2
    b : int = 3
    c : int

    multiply :: fn(x, y: int) -> int {
        return x * y
    }

    my_function : fn(x, y: int) -> int

    my_function = multiply
    c = my_function(a, b)
    println(c) // Prints 6

    my_function = add
    c = my_function(a, b)
    println(c) // Prints 5
}
```

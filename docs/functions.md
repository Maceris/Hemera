# Functions

Functions are defined using `fn`. Below is a function named `say_hello` that takes no input, returns no output, which will print "hello" when called.

```
say_hello :: fn() {
    println("hello")
}
```

Inputs to functions can be provided in the parenthesis. Arguments with default values must all come after any that do not have default arguments.

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

get_two_numbers :: fn() -> (int, int) {
    return 2, 3
}

get_coordinates :: fn() -> (x, y: int) {
    // Outputs act like variables in scope
    x = 4
    y = 5
    return x, y
}

no_return_value :: fn(x: int, y: ptr[int]) {
    if (x < 0) {
        // if returning in a function that does not have any return values, return void is used
        return void
    }
    y^ = x + 5
}
```

Note that the `::` is actually 2 operators, a type could be provided instead of deduced, but that's usually quite redundant.
Below is an example that defines a type which might communicate more intent.

```
BinaryIntFunc :: fn(int, int) -> int
// equivalent to:
// BinaryIntFunc : type : fn(int, int) -> int

add_numbers : BinaryIntFunc : fn(x, y : int) -> int {
    return x + y
}
```

## Named Parameters

```
create_rectangle :: fn(x, y: int, width, height: int) -> Rectangle {/* ... */}

example :: fn() {
    // These are all equivalent
    create_rectangle(1, 2, 50, 75)
    create_rectangle(1, 2, width=50, height=75)
    create_rectangle(x=1, y=2, width=50, height=75)
}
```

Positional and named arguments can be mixed, but named arguments must always be provided after the positional ones.

```
example :: fn(a: int, b: string, c: bool, d: f32, e := 0) {/* ... */}
example(123, "test", c=true, d=1.23)
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

Nested functions cannot access local variables from the outer function.
It's like the inner function being hoisted out into the global scope, but without the name being defined.

```
foo :: fn() {
    x : int = 5

    bar :: fn() {
        // x = 2 // This would not work, it cannot access the scope of foo
    }
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

## Complicated Function Return Types

Functions need to have parenthesis around the return type(s) if

* There is more than one value
* Any results are named
* The result is a function

The parenthesis are to ensure an unambiguous definition, but do not represent tuples.
Functions are always wrapped in parenthesis, even if in a list of types.

```
implicitly_no_return    :: fn() {/* ... */}
explicitly_no_return    :: fn() -> void {/* ... */}
one_result              :: fn() -> int {/* ... */}
one_result_still_same   :: fn() -> (int) {/* ... */}
ptr_result              :: fn() -> ptr[Walrus] {/* ... */}
named_result            :: fn() -> (x: int) {/* ... */}
two_results             :: fn() -> (int, int) {/* ... */}
two_named_results       :: fn() -> (x, y: int) {/* ... */}
three_named_results     :: fn() -> (a: u16, b, c: f32) {/* ... */}
returning_pure_fn       :: fn() -> (fn()) {/* ... */}
returning_a_fn          :: fn() -> (fn() -> int) {/* ... */}
ret_a_fn_with_2_returns :: fn() -> (fn() -> (int, int)) {/* ... */}
returning_int_and_fn    :: fn() -> (int, (fn() -> int)) {/* ... */}
returning_fn_and_int    :: fn() -> ((fn() -> int), int) {/* ... */}
```

Some higher order function definitions can (should) be simplified quite a bit using type aliases.

```
AbsurdFnType : type : fn(fn(int) -> int) -> (fn(int) -> (result, error: int))
nicer_definition :: fn() -> AbsurdFnType {/* ... */}
```

## Variable Arguments

Variable number of arguments can be provided using `...`, after the type of argument.

```
format :: fn(format: string, args: any...) -> string {/* ... */}
```

Within the function the arguments will be treated as if it were an array view.
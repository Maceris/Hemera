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

### Default Values

A parameter's default can be any expression that fits its type. It's checked with the function, using the names the
function's own package sees, before the parameters exist, so it can't use them. It runs each time a call leaves the
parameter out, in the caller, with the caller's context: `allocator := context.allocator` is the caller's allocator.

```
read_all :: fn(file: File, buffer_size: usize = PAGE_SIZE * 4, allocator := context.allocator) -> (u8[], Error?) {/* ... */}
```

Parameters that are pointers, or contain them (views, strings, `any`), can't be kept after the call returns
unless they are marked `#escaping`, since the caller may have passed something on its stack.
See [memory.md](memory.md#escaping-parameters).

```
remember :: fn(registry: ptr[mut Registry], name #escaping : string) {
    array_add(&registry.names, name)
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
It's like the inner function being hoisted out into the global scope, but without the name being defined. A nested
function has one name, and can't be generic yet. It does see the types declared before it in the function (see
[types.md](types.md#types-declared-in-functions)), and in a generic function's instance, that instance's generic
parameters.

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

A function that might not be there is an optional function type. With a result, the function type goes in parentheses,
so the `?` is the function's: without them, it's the result's.

```
Handler :: struct {
    on_done : fn()?,                    // no result: the function is optional
    on_value : (fn(n: int) -> int)?,    // an optional function returning an int
    find : fn(key: string) -> int?,     // a function returning an optional int
}

call_or :: fn(handler: (fn(n: int) -> int)?, n: int) -> int {
    match handler {
        case Some(function) => return function(n)
        case None => return n
    }
}
```

### Defaults in Function Types

A function type can give its parameters defaults too, as [a function does](#default-values), any expression that fits
the parameter's type: checked with the names the package and file where the type is written see, and run in the caller,
with the caller's context, each time a call leaves the parameter out. A named function type's defaults, like an
alias's, are checked where it's declared; a type written in place, like a field's, has its checked with the first call
that leaves one out. `base`'s `AllocatorFn` gives its location one, so a call through an allocator needn't pass it:

```
AllocatorFn :: alias fn(allocator_data: rawptr, size: usize, alignment: usize, old_memory: rawptr, old_size: usize,
    location := #caller_location) -> (mut u8[], AllocatorError?)

memory, error :: context.allocator.function(context.allocator.data, 64, 8, null, 0)
```

Defaults aren't part of a function type's identity: function types that differ only in their defaults are the same
type to convert between, so a function converts to any type with its parameters, whatever either's defaults are.
They're a convenience for callers, not a promise about the function. Which defaults a call uses is decided by how it's
written, never by what the compiler can work out:

* A call through the name of a function, or a constant naming one, uses the function's defaults.
* Any other call, through a variable, parameter or field, or any other expression, uses the defaults of the callee's
  type.

A function that states its type takes the type's defaults: a parameter it gives no default gets the type's, and one
it gives a default must be given the type's, written the same (error E4038 otherwise). A function that wants defaults
of its own doesn't state the type, and still converts to it.

```
FooFn :: alias fn(a: int, b: int = 1) -> int

foo : FooFn : fn(a: int, b: int) -> int {      // b = 1, from FooFn
    return a + b
}

bar : FooFn : fn(a: int, b: int = 2) -> int {  // error E4038: FooFn gives b the default 1
    return a + b
}

qux :: fn(a: int, b: int = 2) -> int {         // its own default, since it doesn't state FooFn
    return a + b
}

twice :: fn(f: FooFn) -> int {
    return f(1) + f(1)                         // FooFn's default: f(1, 1), whatever f is
}

main :: fn() {
    println(qux(1))     // 3: qux's default
    println(twice(qux)) // 4: FooFn's
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
returning_optional_fn   :: fn() -> (fn() -> int)? {/* ... */}
named_fn_result         :: fn() -> (n: int, f: (fn() -> int)) {/* ... */}
```

Some higher order function definitions can (should) be simplified quite a bit using type aliases.

```
AbsurdFnType : type : fn(fn(int) -> int) -> (fn(int) -> (result, error: int))
nicer_definition :: fn() -> AbsurdFnType {/* ... */}
```

# Several Names in One Declaration

A declaration can name several things at once: each takes its own value, in order, or one value gives them all, like
a call's several results. A type written once is each one's.

```
x, y, z := 0, 1, 2
width, height : u32 = 640, 480
MIN, MAX :: -10, 10          // at the top level too, as if written apart
quotient, remainder := divide(7, 2)
low, high, extra := divide(7, 2), 9
```

The values have to match the names: as many as there are, counting a call's results, or one.

# Ignoring Return Values
If a function has multiple return values, you can indicate that you'd like to
ignore one or more by using `_`.

```
find_vowels :: fn(text: string) -> (count: int, found_any: bool) {/* ... */}

foo :: fn() {
    relevant: bool
    _, relevant = find_vowels("somewhere")

    // These 2 are equivalent
    _, _ = find_vowels("else")
    find_vowels("else")
}
```

When using any kind of special assignment, all values must be of types that make sense
for that operator to apply.

```
multiple_returns :: fn() -> (a: A, b: B) {/* ... */}

foo :: fn() {
    c: C
    d: D

    c, d += multiple_returns()
    // c += a and d += b must make sense
    // e.g. C and A must be integral types that we can add without casting weirdly
    // And similarly D and B must be compatible
    // None of these types could be booleans, for example, as "+" doesn't apply to those
}
```

Here is a more concrete example.
```
multiple_returns :: fn() -> (i64, u8) {/* ... */}

foo :: fn() {
    c: i64
    d: u16

    // This is fine:
    // c can have another i64 added to it
    // a u8 can be implicitly cast up to a u16 and added to d
    c, d += multiple_returns()

    // This is an error:
    // i64 cannot be implicitly cast to the smaller (and unsigned) u8
    // The u8 can't cast to i64 either, as the signed-ness changes
    d, c += multiple_returns()
}
```

## Variable Arguments

Variable number of arguments can be provided using `...`, after the type of argument.

```
format :: fn(format: string, args: any...) -> string {/* ... */}
```

Within the function the arguments will be treated as if it were an array view.

The variable argument can be passed to another function's variable arguments of the same type.

```
foo :: fn(format: string, numbers: int...) {
    bar(true, numbers, false)
}

bar :: fn(fiz: bool, some_numbers: int..., fuzz: bool) {
    // ...
}
```

A variadic parameter can have others after it, more variadic ones among them, as long as a call can always tell
where each one's values end. It takes the values that fit it, in order, and the first that doesn't goes to the
parameter after it, so its type and the types of the parameters a value after it could go to can't be taken for each
other: neither converts to the other implicitly, and no literal fits both. That runs up to the first parameter after it
that isn't variadic, since each variadic one may be given nothing. A parameter between two groups can't be taken for
the variadic one after it either.

```
bar(false, 1, 2, 3, true)   // some_numbers is 1, 2, 3; fuzz is true
bar(false, true)            // some_numbers is empty

groups :: fn(names: string..., numbers: int..., flags: bool...)   // fine: no two can be taken for each other
around :: fn(names: string..., middle: int, points: Point...)      // fine

bad :: fn(fiz: bool, some_numbers: int..., fuzz: f32)        // error: an untyped 3 could be an int or the f32
worse :: fn(names: string..., numbers: int..., more: string...)  // error: with no numbers, a string could be either
```

A value that takes its type from where it goes, like `.{x = 1}`, `.Member` or `null`, is the variadic parameter's
while it's taking values. A parameter with a default right after a variadic one is only given by name, or left to its
default, so it's never the boundary: `log_info(format_string: string, params: any..., location := #caller_location)`
gives every value after the format to `params`.

## Functions Still to Write

A function that isn't written yet calls `todo()`, a builtin that never returns: reaching it calls
`context.assertion_handler` with its message, which ends the program. Since it doesn't return, a function whose
body is `todo()` doesn't need a `return`, and still type-checks.

```
parse_config :: fn(text: string) -> Result[Config, ParseError] {
    todo("parse the config format")
}
```

An empty body is an error in a function with results, since it would finish without returning them.

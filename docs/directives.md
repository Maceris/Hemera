# Directives

## Compilation

`#assert` is used to check conditions at compile time. If the condition evaluates to false, 
we stop the build and throw an error.

```
#assert size_of(Foo) >= size_of(Bar)
```

We also have a runtime assert, where the handler can be specified, and the compiler
will behave similarly if you do a `#run assert(/*...*/, "Custom error here")`, but that version
allows for a specific error message instead of the `#assert /* expression */` reporting style.

The runtime `assert` calls `context.assertion_handler` when the assertion is false, which can be changed with
`push_context`. Handlers are expected to end the program. If a handler returns anyway, `assert` stops the program
with `intrinsics.trap()` (an illegal instruction), so execution never continues past a failed assertion.
At compile time, that fails the build.

`#if` used to conditionally include sections of code, evaluated (as in chosen, not executed) at compile time.
The boolean expression is executed at compile time, but the block is either included in the code or not. 
Also used with `#else_if` and `#else`.

```
foo :: fn() {
    #if OS == .WINDOWS {
        init_socket() 
    }
}
```

`#is_compile_time` evaluates to `true` during compile time and `false` during run time.

`#run` specifies code should be run during compile time. It is followed by an expression to execute.

When the `#run` directive appears at the top level of a file, it is executed when that file gets processed (each unique file should be processed once).
When included in the body of a function, it is executed when that function is processed.
When included in places like the right-hand side of an expression, function arguments, etc. it will be evaluated as an expression and the result used as if it were
a constant value.

```
#run println("I am processing a file")

example :: fn() {
    #run println("I am processing example()")

    // equivalent to writing some_fn(21), assuming fibonacci() behaves as expected
    some_fn(#run fibonacci(8))
}
```

## Control

`#at_least_once` causes a loop operation to occur at least once, skipping the first condition check. This is equivalent to turning a C while loop into a do-while loop.

`#fall_through` is used in switch statements to fall through (continue on) to the next case.

`#reverse` indicates a loop over a range should be done in reverse, for example:

```
for i in 0..=10 #reverse {
    println(value)
}
```

## Enums

`#backed_by(x)` is used to specify `x` as the backing type, which must be one of the unsigned integer types (u8, u16, u32, u64, u128). By default enums are backed by uint.

## Functions

`#export` on a function marks it as part of a library or program's public interface.
This is placed after the identifier in a declaration.

```
example #export :: fn() {/* ... */}
```

You could in theory put this on a function inside other functions, as they are effectively hoisted out anyway.
However that is a fairly confusing thing to do, since it's visible outside the program by name but must be passed 
around by function pointer inside the program, so it's discouraged.

## Function Parameters

### `#caller_location`

`#caller_location` is (only) used to set a function parameter's default value to the location of the code calling the function.

### `#escaping`

`#escaping` marks a parameter that the function may keep after it returns, for example by storing it on the heap.
Callers can't pass anything that points into their stack to it.
Parameters that carry pointers and aren't marked can't be kept. See [memory.md](memory.md#escaping-parameters).

It is placed after the parameter's name, and is part of the function's type.

```
register :: fn(registry: ptr[mut Registry], name #escaping : string) {/* ... */}
Callback :: alias fn(data #escaping : any)
```

## Structs

`#align(n)` is used to align to `n` bytes, for example `struct #align(8) {...}` aligns the struct to 8 bytes.
`#packed` is used to remove padding between fields in a struct
`#union` turns the struct into a c-style union, where every field is located at the same offset and share memory
`#scoped` is used for structs meant to hold pointers into the stack and be passed around by pointer, like parsers and iterators over a stack buffer.
Values of these structs can never be stored on the heap. See [memory.md](memory.md#scoped-structs).

## Values

`#file_path` is the path to the file in which this directive appears.


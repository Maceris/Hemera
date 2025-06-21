# Directives

## Compilation

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

## Control

`#at_least_once` causes a loop operation to occur at least once, skipping the first condition check. This is equivalent to turning a C while loop into a do-while loop.

`#fall_through` is used in switch statements to fall through (continue on) to the next case.

`#reverse` indicates a loop over a range should be done in reverse, for example:

```
for i in 0..=10 #reverse {
    println(value)
}
```

## Function Parameters

### `#caller_location`

`#caller_location` is (only) used to set a function parameter's default value to the location of the code calling the function.

## Values

`#file_path` is the path to the file in which this directive appears.


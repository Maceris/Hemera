# Directives

## Compilation

`#if` used to conditionally include sections of code, evaluated at compile time.
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

`#reverse` indicates a loop over a range should be done in reverse

```
for i in 0..=10 #reverse {
    println(value)
}
```

## Procedure Paremeters

### `#caller_location`

`#caller_location` is (only) used to set a function parameter's default value to the location of the code calling the function.

## Procedures

## Statements

## Values


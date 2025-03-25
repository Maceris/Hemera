# Directives

## Compilation

`#compile_time` - indicates code should be executed at compile time, valid for

* if-else statements
* function calls

`#if` used to conditionally include sections of code, evaluated at compile time. Intended more for things like includes, definitions, and scope members rather than optionally executing blocks of code.
Also used with `#else_if` and `#else`.

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


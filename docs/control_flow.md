# Control Flow

## Defer

The `defer` keyword is used to defer a statement until the end of a block. It will be executed before leaving the block,
whether that is by reaching the end, having a `return`, `break`, `continue`, or anything else.


```
foo :: fn() {
    defer println("This prints last")
    defer println("This prints second")
    println("This prints first")
}
```

When there are multiple `defer` statements, they will execute in reverse order from how they appear, as if being pushed onto a stack.
The reason for this is we usually want to clean up resources in the reverse order of their creation, and this allows
sub-resources to be cleaned up before parent resources which were used to create them.

```
foo :: fn() {
    a := new A()
    defer delete a

    b := new B(a)
    defer delete b

    // b is cleaned up here
    // a is cleaned up here
}
```

This works in any block and whole expressions can be provided. Here is a more complex example involving loops:

```
foo :: fn() {
    with {
        i : int = 0
        matched : bool = false
    }
    loop {
        defer i += 1
        defer matched = false
        defer println()
        defer if !matched { print(i) }

        if i % 3 == 0 {
            print("fizz")
            matched = true
        }
        if i % 5 == 0 {
            println("buzz")
            matched = true
        }

        if i % 8 == 0 {
            // be careful, defers all run here too
            break
        }

        // "if !matched { print(i) }" runs here
        // "println()" runs here
        // "matched = false" runs here
        // "i += 1" runs here
    }
    while(i <= 10)
}
```

## Loops

### Loop control statements

`break` can be used to break out of the current loop.

A positive integer can also be provided to break out of multiple loops like `break 2` 
will break out of 2 layers of loops (or similar structures where `break` applies).

Finally, `break all` will break out of all loops (or similar structures where `break` applies).

`continue` will skip the rest of the current iteration of a loop, and continue again at the beginning.

### Range-based for
```
// 0 to 10, excluding 10
for i in 0..<10 {
    println(i)
}

// 0 to 10, including 10
for i in 0..=10 {
    println(i)
}

// The bounds can be variables, expressions
for i in x..<random_integer() {

}

some_array : int[3] : {1, 3, 19}

for value in some_array {
    println(value)
}

// You can add an optional second parameter for the index number 
for value, index in some_array {
    println(value)
}
```

You can iterate arrays and views by reference:

```
for &value in some_array {
    println(value)
}

// Index is not affected
for &value, index in some_array {
    println(value)
}
```

The `#reverse` directive indicates a loop should be done in reverse

```
for i in 0..=10 #reverse {
    println(i)
}
```

### While

```
loop {
    println("This is an infinite loop")
}
```

`while` is used to specify a condition that must be true for a loop to execute. It appears at the end, which has nothing to do with when the condition is checked. It is always checked *before* running the loop, besides when using a directive that will be discussed later.

`with` is used to define things that are in scope for the body of the loop (and condition).

`with` behaves as if wrapping the whole loop in a new block scope. So 
anything declared there is not in scope after the loop, and any `defer`s
appearing in the `with` execute *after* the loop completes (or breaks, returns, etc.).

The following is equivalent to `for (int i = 0; i <= 10; ++i) println(i)` in C++.

```
with {
    i : int = 0
}
loop {
    println(i)
    i += 1
}
while(i <= 10)
```

`#at_least_once` causes a loop operation to occur at least once, skipping the first condition check. This is equivalent to turning a C while loop into a do-while loop.

```
loop #at_least_once {
    println("This will run")
}
while(false)

loop {
    println("This will not run")
}
while(false)
```

## Match

Match expressions evaluate to a value using pattern matching.

The cases can be any of these types:

* Integer (including ranges)
* Character (including ranges)
* String
* Enums
* Unions

Example:
```
result : string : match foo {
    1 => "a"
    2, 3 => "b"
    4..=10 => "c"
    _ => "x"
}

result2 : int = match bar {
    Ok(foo, _) => foo + 1
    Fail(_) => 0
    _ => -1
}
```

## Switch

Switch statements work similar to C's, except they never fall through except where a directive is explicitly provided to do so.

The cases can be any of these types:
* Integer (including ranges)
* Character (including ranges)
* String
* Enums

Example:
```
switch foo {
    case 1: print("a")
    #fall_through
    case 2, 3: print("b")
    case 4..=10: print("c")
    case _: print("x")
}
```

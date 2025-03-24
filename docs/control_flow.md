# Control Flow

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
    println(value)
}

// 0 to 10, including 10
for i in 0..=10 {
    println(value)
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
    println(value)
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

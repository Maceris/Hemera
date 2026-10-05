# Control Flow

## Conditionals

The `if` and `else` keywords are used for conditional branching. If is directly followed by any expression that evaluates to a boolean. All if's and else's require curly braces.

If/else statements can be chained, as in `if ... else if ... else if ... else ...`.

```
foo :: fn() {
    bool b = is_it_tuesday()

    if b {
        println("b is true")
    }
    else if 5 >= 3 + bar() {
        println("I'm not sure what this is supposed to be for")
    }
    else {
        println("b is false")
    }
}
```

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
while i <= 10
```

`#at_least_once` causes a loop operation to occur at least once, skipping the first condition check. This is equivalent to turning a C while loop into a do-while loop.

```
loop #at_least_once {
    println("This will run")
}
while false

loop {
    println("This will not run")
}
while false
```

## Match

Match expressions evaluate to a value using pattern matching.

The cases can be any of these types:

* Integer (including ranges)
* Character (including ranges)
* String
* Enums
* Unions
* Boolean

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

## Push Context

The context can't be modified. To use a different one, the `push_context` keyword is used, which does two things:

1. Defines a new context: a copy of the current context, with the listed fields overridden.
2. Saves the current context, uses the new one for the block (and every function called from it),
   then switches back to the saved one when the block is left.

```
push_context my_context (allocator = memory.ArenaAllocator, log_level = .WARN) {
    // context in this block, and any function calls in it, is referring to my_context
    print_something("You can do whatever you want here")
}
// back to the previous context here
```

* At least one field must be listed, and each field at most once. Fields not listed keep their current values.
* Override values can't point into the stack (see [memory.md](memory.md#contexts)),
  so a context can always be copied, for example into a new thread or fiber.
  A trailing comma is allowed, as in other lists.
* The override expressions are evaluated in order, before the switch, so they see the old context.
  For example, in `push_context scratch (allocator = make_arena(context.allocator))`, the arena gets its memory
  from the allocator that was current before the push.
* `my_context` names the new context inside the block. It refers to the same value as `context` there,
  and is read-only like it. The name is useful for referring to an outer context from inside a nested `push_context`.
* The new context lives in the current function's stack frame, and is destroyed when the block is left.
  That happens however the block is left: reaching its end, `return`, `break` or `continue`.
  `defer` statements inside the block run before the old context is restored, so they still see the new one.
* New threads and fibers get a copy of the context that was current when they were created
  (see [multitasking.md](multitasking.md#contexts)).

### The Context is Read-Only

The compiler rejects anything that would change the current context, rather than replace it for a scope:

```
context.allocator = memory.ArenaAllocator   // Error: the context can't be assigned to
context.allocator.data = some_data          // Error: neither can any of its fields, at any depth
context = other_context                     // Error
x : ptr[mut Allocator] = &context.allocator // Error: no mutable pointers into the context
modify_allocator(&context.allocator)        // Error, if the parameter is ptr[mut Allocator]
```

Fields that are pointers, like `logger : ptr[Logger]`, follow the usual rules for what they point to:
`ptr[Logger]` isn't `mut`, so the logger can't be modified through it either.
State that does need to change, like an allocator's or a random number generator's, is changed by calling
the functions they hold, which receive their data pointer as `mut`.

These checks are for well-behaved code. Laundering a pointer to the context through `rawptr` or a cast can get
around them, and the result is undefined behavior.
The point of pushing contexts is that a function can rely on the context it was given, and can't change
the allocator or logger out from under the function that called it.

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

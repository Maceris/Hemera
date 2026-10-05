# Memory

Hemera operates under, and will use operating system utilities to enforce whenever possible,
the model that all memory is either writable or executable but never both.

# Pointers to the Stack

Pointers and views can refer to stack memory: `&local_variable`, a stack array passed as an array view,
an `any` made from a local variable. The compiler checks that none of them can outlive the stack frame
(or block) they point into.

The checks are deliberately much smaller than a borrow checker:

* There are no lifetime annotations or lifetime variables. The only annotations are `#escaping` on parameters
  and `#scoped` on structs, and most code needs neither.
* There are no rules about aliasing or exclusive access. Any number of pointers, mutable or not, can refer
  to the same thing.
* Each function is checked on its own, using only the signatures of the functions it calls.
* Only stack memory is covered. Using heap memory after it's freed is not checked (see [Not Checked](#not-checked)).

## Local and Unrestricted Values

Every value whose type contains pointers (pointers, `rawptr`, array views, strings, `any`,
and structs, unions and arrays containing any of those) is either **local** or **unrestricted**.
Values of types without pointers are always unrestricted.

A value is local if it is, or was computed from:

* the address of a local variable or parameter, or of any part of one (`&x`, `&x.field`, `&x[i]`)
* a view of a stack array (`buffer[5]`, or passing `buffer` where a view is expected)
* an `any` made from a local variable or parameter
* a parameter that isn't marked `#escaping`
* any value of a `#scoped` type
* a value loaded through a deep pointer (below)
* the result of a call, when any argument to a non-`#escaping` parameter was local (see [Returning](#returning))

Everything else is unrestricted, including results of `new`, values loaded through other pointers,
and `#escaping` parameters.

Each local value has an *origin*: the block whose variables it points into, or the parameter it came from.
When a value is computed from several local values, its origin is the shortest-lived of theirs.

### Deep Pointers

A pointer to a location that holds local values is *deep*: whatever is loaded through it is local too.
Only two kinds of values may be deep:

* pointers to `#scoped` types (see [Scoped Structs](#scoped-structs))
* `any` values, so that `log_info("%", name)` works when `name` is a string viewing a stack buffer

Deep stays deep through casts, so a `rawptr` taken from a deep `any` and cast to a typed pointer is still deep.
Inside a function, `any` parameters and pointer-to-`#scoped` parameters are treated as deep, since the caller may
have passed deep ones.

Taking an ordinary pointer (`&x`, or an array view) to a location that holds a local value is an error.
A stack struct holding a view of a stack buffer can be passed by value or as an `any`, but `&` on it needs the struct
to be `#scoped`.

This keeps the invariant that memory that a non-deep pointer can reach never contains a local value.
That is why loading through an ordinary pointer, including one passed as a parameter, gives an unrestricted value,
and why each function can be checked without looking inside the functions it calls.

## Rules

A local value may be:

* passed as an argument to a parameter that isn't `#escaping`
* stored in a local variable (or a field or element of one), as long as that variable doesn't outlive the
  value's origin
* returned, if its origin is a parameter

The compiler reports an error when a local value would be:

* returned, when it points into the function's own frame
* stored into a variable declared in an outer block than the one it points into
* stored through a pointer (`p^ = x`, `p.field = x`, `p[i] = x`), except as described for `#scoped` types
* passed to an `#escaping` parameter
* used as a `push_context` override (see [Contexts](#contexts))
* made into an ordinary (not deep) pointer to a location holding a local value, see [Deep Pointers](#deep-pointers)

```
sum :: fn(values: int[]) -> int { /* ... */ }

bad_return :: fn() -> ptr[int] {
    x := 5
    return &x                                   // error: returns a pointer into this frame
}

example :: fn() {
    buffer : int[16]
    total := sum(buffer)                        // OK: sum doesn't keep its parameter
    log_info("total is %, first is %", total, buffer[0])   // OK: the any... values don't escape

    p : ptr[int]
    {
        y := 1
        p = &y                                  // error: p outlives y
    }

    holder := Holder.{ values = buffer[..] }
    use_holder(holder)                          // OK: passed by value
    use_holder_pointer(&holder)                 // error: holder holds a local value and Holder isn't #scoped
}
```

The check is flow-insensitive within a function: if a variable is ever assigned a local value, it's treated as
local everywhere, and if it ever holds one, `&` on it is an error everywhere. Use a different variable for values
with different origins.

Taking the address of a parameter that carries pointers (`&s` where `s` is a `string` parameter) is an error for
the same reason, since the parameter holds a local value. Pass it by value instead.

## Escaping Parameters

Parameters that can carry pointers don't escape unless they are marked `#escaping`.
Inside the function, a non-escaping parameter is a local value whose origin is the parameter, so it can be read,
passed on to other non-escaping parameters, and returned (see [Returning](#returning)), but not stored anywhere that
outlives the call.

A function that does keep a pointer it was given marks that parameter, and callers can then only pass
unrestricted values to it:

```
Registry :: struct { names : string[..] }

register :: fn(registry: ptr[mut Registry], name #escaping : string) {
    array_add(registry.names, name)         // without #escaping: error, `name` is stored somewhere
}                                           // that may outlive this call, mark it #escaping

example :: fn(registry: ptr[mut Registry]) {
    name_bytes : u8[32]
    // ...
    register(registry, string_from(name_bytes))   // error: stack data passed to #escaping parameter `name`.
                                                  // Copy it to the heap first.
}
```

The error is always reported in the function that stores the pointer, or at a call that passes stack data to an
`#escaping` parameter, so it shows up where the fix is.

For generic parameters, `#escaping` only matters when the type argument contains pointers.
`array_add`'s `value` is `#escaping`, but adding an `int` to an array doesn't care.

`#escaping` is part of a function's type. In function types, a parameter has to be named to be marked:
`fn(data #escaping : any)`. A function whose parameter doesn't escape can be used where the type says it does
(callers only pass unrestricted values, which is always fine), but not the other way around.

Function values are never local: nested functions can't capture local variables, so a function value never
points into a stack frame.

## Returning

Functions often return views of what they were given, like `trim(s: string) -> string`. That needs no annotation:

* Inside the function, returning a value whose origin is a parameter is allowed.
* At the call site, the result is local if any argument to a non-`#escaping` parameter was local, with the
  shortest-lived origin among them. It's unrestricted otherwise.

This is conservative. `lookup(table: ptr[Map], key: string) -> ptr[Value]` called with a key on the stack returns a
local value, even if it really points into the table's heap memory. That only matters when storing the result
somewhere that outlives the key. You can however copy the key to the heap first.

## Scoped Structs

A struct marked `#scoped` is meant to hold pointers into the stack, and to be passed around by pointer.
This is for things like parsers and iterators over a stack buffer, or builders writing into a stack array.

```
Parser :: struct #scoped {
    input : u8[],
    line : u32,
}

advance :: fn(parser: ptr[mut Parser]) {
    parser.input = parser.input[1..]        // OK: stores a value derived from parser back through parser
    parser.line += 1
}

parse :: fn() {
    buffer : u8[256]
    // ... fill the buffer ...
    parser := Parser.{ input = buffer }
    advance(&parser)                        // OK: Parser is #scoped
}
```

* Every value of a `#scoped` type is local, and pointers to one are deep, so anything loaded through them is local.
* A `#scoped` type can't be stored on the heap: in a field of an ordinary struct, in heap-allocated arrays,
   in an `any` that escapes, or passed to an `#escaping` parameter.
* Through a pointer to a `#scoped` type, a function may store unrestricted values, and local values whose origin is
  that same pointer (usually ones it loaded through it). Storing values with any other origin is an error, since
  they might not live as long as the struct.

Ordinary structs can hold local values too, as long as nothing takes their address.

## Contexts

`push_context` overrides must be unrestricted values. So everything reachable from a context is unrestricted, and
a context can always be copied, including into new threads and fibers.

A context can't use an allocator whose memory is a buffer on the stack, for example.

## Threads and Fibers

`thread_create`, `fiber_create` and similar functions take their `data` as `#escaping`, since the new thread or
fiber outlives the call. A new thread or fiber can't be handed a pointer into the creating function's stack frame.

Fiber stacks never move (see [multitasking.md](multitasking.md#stacks)), so local values stay valid across yields,
even when a fiber moves to another OS thread.

## Casts

* Casting a local pointer to `rawptr`, or a `rawptr` to a typed pointer, keeps it local, and deep if it was deep.
* Casting a pointer to an integer (`uintptr`) stops tracking. Integers are always unrestricted, so a pointer cast to
  an integer and back is unrestricted. Doing that to get around these checks is undefined behavior,
  the same as laundering a pointer to the context.

## Not Checked

* Using heap memory after it has been freed, including a view into a dynamic array that has since grown and moved.
  Debug allocators are the tool for these.
* Pointers laundered through integers.
* Data races. Pointers to the stack can be handed to other threads only through `#escaping` parameters,
  which don't accept them, but heap pointers can be shared freely.

## Prior Art

* C#'s `ref struct`, `Span<T>` and `scoped`: local "safe-to-escape" rules, which `#scoped` structs are modeled on.
* Swift: closures don't escape unless marked `@escaping`, which `#escaping` is named after.
  Swift has since added non-escapable types and `Span`.
* D's `scope` parameters: a warning to keep the set of annotations small.
* Go's escape analysis: the same analysis, but Go moves escaping values to the heap instead of reporting them.
  Hemera's allocations are explicit, so it reports an error.

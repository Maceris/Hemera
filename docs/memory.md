# Memory

Hemera operates under, and will use operating system utilities to enforce whenever possible,
the model that all memory is either writable or executable but never both.

# Allocators

Memory comes from an `Allocator` (`base/runtime/core.hsc`), usually `context.allocator`: a function and its data.
The one function allocates, frees and resizes:

```
AllocatorFn :: alias fn(allocator_data: rawptr, size: usize, alignment: usize, old_memory: rawptr, old_size: usize,
    location := #caller_location) -> (mut u8[], AllocatorError?)
```

* With `old_memory` null, it allocates `size` bytes aligned to `alignment`, a power of two.
* With `size` 0, it frees `old_memory`.
* With both, it resizes `old_memory` to `size` bytes, keeping its alignment.

Freeing and resizing pass the block's `old_size` and `alignment` as it was allocated, so an allocator can find a block
from them, like one that keeps blocks of each size and alignment apart and has no header to read. `base`'s functions
come in pairs that keep this: `free` gives back what `new` made and `free_array` what `new_array` made, each with the
type's own alignment, and `free_aligned` and `free_array_aligned` what `new_aligned` and `new_array_aligned` made,
given the same alignment again.

```
block, error :: new_array_aligned(u8, 4096, 64)
// ...
free_array_aligned(block, 64)
```

# Pointers to the Stack

Pointers and views can refer to stack memory: `&local_variable`, a stack array passed as an array view,
an `any` made from a local variable. The compiler checks that none of them can outlive the stack frame
(or block) they point into.

The checks are deliberately much smaller than a borrow checker:

* There are no lifetime annotations or lifetime variables. The only annotations are `#escaping` on parameters,
  and `#scoped` and `#unrestricted` on structs, and most code needs none of them.
* There are no rules about aliasing or exclusive access. Any number of pointers, mutable or not, can refer
  to the same thing.
* Each function is checked on its own, using only the signatures of the functions it calls.
* Only stack memory is covered. Using heap memory after it's freed is not checked (see [Not Checked](#not-checked)).

## Local and Unrestricted Values

Every value whose type contains pointers (pointers, `rawptr`, array views, strings, `any`,
and structs, unions and arrays containing any of those) is either **local** or **unrestricted**.
Values of types without pointers, and of `#unrestricted` structs, are always unrestricted.

A value is local if it is, or was computed from:

* the address of a local variable or parameter, or of any part of one (`&x`, `&x.field`, `&x[i]`)
* a view of a stack array (`buffer[5]`, or passing `buffer` where a view is expected)
* an `any`, which points at a copy of the value in the stack frame that made it (see [types.md](types.md#any))
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
    array_add(&registry.names, name)        // without #escaping: error, `name` is stored somewhere
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

A pointer to a local variable counts the same way: `take(&arena, count)` gives a local view, whatever memory the arena
hands out. When what's returned really comes from elsewhere, keep the stack out of the call: pass the state by value
or keep it somewhere other than the stack, or make the handle `#unrestricted` (below) and pass it by value.

### Unrestricted Results

A function whose result never points at what it was given, like one that copies into memory from an allocator, marks
that result `#unrestricted`, the way a parameter is marked `#escaping`. After the results, it marks every one of them,
and after a named result, just that one:

```
clone :: fn(text: string, allocator := context.allocator) -> Result[string, AllocatorError] #unrestricted {
    // ... copies text into new memory ...
}

split_off :: fn(text: string, allocator := context.allocator) -> (copy #unrestricted : string, rest : string) {/* ... */}

example :: fn(registry: ptr[mut Registry]) {
    name_bytes : u8[32]
    // ...
    match clone(string_from(name_bytes)) {
        case Ok(name) => register(registry, name)   // OK: the copy is unrestricted, though name_bytes is on the stack
        case Error(_) => {}
    }
}
```

An unrestricted `Result` or optional is unrestricted whatever it holds, so what `case Ok(name)` or `or_else` takes out
of it is too. That's what lets a function that allocates give one value back, rather than a value and an error.

* At the call site, the result is unrestricted whatever the arguments were.
* Inside the function, returning anything local there is an error, including a value whose origin is a parameter,
  since the caller's arguments may be on its stack.
* It's part of the function's type: a function whose result is `#unrestricted` can be used where the type's result
  isn't, but not the other way around.

`std/strings`' `format` and `clone`, and `std/os`'s functions that allocate, like `read_entire_file`, are marked this
way.

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
* A `#scoped` type can't be stored on the heap: in a field of an ordinary struct, in a dynamic array (whose elements
   are always on the heap, wherever the array itself is), in an `any` that escapes, or passed to an `#escaping`
   parameter.
* Through a pointer to a `#scoped` type, a function may store unrestricted values, and local values whose origin is
  that same pointer (usually ones it loaded through it). Storing values with any other origin is an error, since
  they might not live as long as the struct.

Ordinary structs can hold local values too, as long as nothing takes their address.

## Unrestricted Structs

A struct marked `#unrestricted` never points into the stack. Its values are always unrestricted, so they can be stored
anywhere, and passing one to a function doesn't make what the function returns local.

```
Allocator :: struct #unrestricted {
    function : AllocatorFn,
    data : rawptr,
}

grow :: fn(list: ptr[mut List], allocator: Allocator, loc := #caller_location) {
    list.items = new_array(Item, list.count * 2, allocator, loc)   // OK: allocator and loc are unrestricted
}
```

This is for handles that are passed to many functions and never made from stack memory, like `base`'s `Allocator` and
`SourceCodeLocation`. Without it, everything allocated through an allocator parameter would be local, since the
parameter is.

* Building one from a local value, or storing a local value in one of its fields, is an error.
* A struct can't be both `#scoped` and `#unrestricted`.

So an allocator whose memory is a buffer on the stack can't be an `Allocator`, as for contexts (below).

## Contexts

`push_context` overrides must be unrestricted values. So everything reachable from a context is unrestricted, and
a context can always be copied, including into new threads and fibers.

A context can't use an allocator whose memory is a buffer on the stack, for example.

The one exception is `extensions`: it may point at a `ContextExtension` node on the stack of the frame doing the
push, whose own `next` follows the same rule. New threads and fibers don't keep those pointers, they get their own
copy of the chain (see [multitasking.md](multitasking.md#context-extensions)). What each node's `data` points to
must still be unrestricted.

## Threads and Fibers

`thread_create`, `fiber_create` and similar functions take their `data` as `#escaping`, since the new thread or
fiber outlives the call. A new thread or fiber can't be handed a pointer into the creating function's stack frame.
The function a thread runs takes its `data` as `#escaping` too (`ThreadFunction`), since that's where it came from.

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
  which don't accept them, but heap pointers can be shared freely. A race isn't undefined behavior, though,
  see [Data Races](#data-races).

## Data Races

Plain loads and stores that race with each other (on different threads, with at least one store, and nothing
ordering them) are defined, not undefined behavior:

* A naturally aligned value no larger than a pointer is read or written in one piece, like a `_no_fence` atomic.
  A racing load sees some value that was stored, possibly an old one, but never a mix of two.
* Larger values may be torn: a racing load can see parts of different stores.
* Nothing orders racing accesses against each other or anything else. That takes atomics and fences
  (`base/intrinsics/atomics.hsc`).

The compiler can't invent loads or stores of shared memory, or assume a value it loaded can't change underneath
it, so races give stale or torn values, but never break unrelated code.

# Secrets

Code that works with secrets, like keys and passwords, mustn't take a time that depends on them: an attacker who can
time it, even across a network, learns the secret a little at a time. So a secret can't decide anything that changes
what runs or which memory is read, and the compiler checks it can't.

A type whose values are secrets is marked `#secret`: a struct, or a distinct alias, which then has the type it aliases
as its public form. A value is a secret when its type is one, or when it's worked out from one: by an operator, a
cast, a literal holding one, or reading a secret's field or element. A local made from a secret holds one too.

```
Key :: struct #secret {
    bytes: u8[32],
}

Word :: distinct alias u32 #secret
```

A secret can't decide:

* a branch: an `if`'s condition, which arm of a `match` or case of a `switch` runs, whether `&&` or `||` runs its
  right side, `or_else`, `or_return` and `?`;
* how long a loop runs: a range's bounds (going through a secret array is fine, since how many elements it has
  isn't a secret);
* which memory is read: an index, or a pointer worked out from one (a secret array indexed by a public index is fine);
* a division: `/`, `%` and `%%` take longer for some values on most CPUs.

What a secret can go into is checked by type, so where secrets cross from one function to another shows in their
signatures: a parameter, a result, or something assigned to, has to be of a `#secret` type, or already hold secrets,
like a field of a secret or a local made from one. Taking a pointer to a secret that isn't of a `#secret` type, like
`&key.bytes`, would lose that it's one, so that's an error too, and so is casting a pointer to a secret, like a
`ptr[Key]`, to a pointer to what isn't. `bit_cast` of a secret gives a secret, so it needs nothing more. `.count` and
`.capacity` aren't secrets.

A `rawptr` is the way past these on purpose: what's read through one, or copied with `intrinsics.mem_copy`, isn't
tracked, so `cast[rawptr](&key)` is where a reviewer looks.

A function whose parameters or results are secrets is marked `#constant_time`, so it shows in its signature. Any
function can hold and work with secrets; the rules above hold everywhere. A `#constant_time` function that works
with no secret at all is warned about, since it's probably left over from one that did.

A generic's instances needn't be marked: `new_array(Key, 4)` makes a secret instance of `new_array`, whose signature
can't say so, and it's checked by the same rules as any function, so a generic that branches on what it's given, like
`array_find`, is an error for secrets, pointing into its body. A generic marked `#constant_time` is meant for secrets,
and isn't warned about for its instances that have none.

```
// Whether two keys are equal, looking at every byte whatever it finds
keys_equal #constant_time :: fn(a: ptr[Key], b: ptr[Key]) -> bool {
    difference := compiler.secret(cast[u8](0))
    for i in 0..<a.bytes.count {
        difference = difference | (a.bytes[i] ~ b.bytes[i])
    }
    return compiler.declassify(difference == 0)
}

larger #constant_time :: fn(a: Word, b: Word) -> Word {
    return intrinsics.select(a > b, a, b)
}
```

* `compiler.declassify(value)` gives a secret as its public form, for what's public by design, like whether a tag
  matched once it's been compared, or ciphertext written to an output. A `#secret` alias's public form is what it
  aliases; a `#secret` struct has none, so what's in it is declassified instead.
* `compiler.secret(value)` makes a value a secret, for a local that will hold secrets, like `difference` above.
* `intrinsics.select(condition, chosen, otherwise)` chooses between integers, bools or enums without a branch: from
  the condition it makes a mask of all ones or all zeros, which it passes through an empty assembly block, so the
  optimizer can't see it's one or the other and turn it back into a branch. With a vector of bools it chooses lane
  by lane (see [types.md](types.md#vectors)).
* Intrinsics take secrets wherever they're given them, since each is an instruction or two that takes the same time
  whatever it's given, and give a secret back for one.
* `intrinsics.secure_zero(target, len)` writes zeros even when nothing reads them after, for wiping a secret.

The compiler checks the source; LLVM has no way to promise what the machine code does. `select` keeps its own
masks from becoming branches, but other code is only as constant time as LLVM leaves it.

## Checking the Machine Code

What the program really does can be checked by running it under Valgrind's Memcheck, the way ctgrind does. Built
with `--valgrind-secrets` for x86-64, `compiler.secret` tells Memcheck its value is undefined, and
`compiler.declassify` that it's defined again. Memcheck follows undefined values through every instruction and
reports a conditional jump or a memory address that depends on one, so anything that depends on a secret, short of
a declassification, is an error:

```
hemera --os=linux --valgrind-secrets --output=check program
valgrind -q --error-exitcode=99 ./check
```

A test program marks what's secret with `compiler.secret`, like `key := compiler.secret(cast[Key](bytes))`, and
calls what it's checking. Outside Valgrind, or built without the flag, nothing changes: Valgrind's requests are
instructions that come to nothing. The compiler's tests run `std/crypto`'s constant-time functions this way on Linux, beside a program that leaks
a secret through a `rawptr`, which Memcheck has to catch.

It checks the paths the test takes, with the values it gives, not every one, and only on the CPU Valgrind
presents, which leaves out some extensions, like x86-64's SHA instructions, so code that uses them when it can
takes its other path there. And Memcheck doesn't report a conditional move on a secret, which passes the secret
on rather than branching, or an instruction whose time depends on its operands, like a division.

# Owned Types

Some values are a resource as well as data: a file to close, memory to give back, a count to drop. A struct marked
`#owned` says each of its values has one owner at a time, and names the function that releases one. The compiler
checks that every owner is released or handed on, on every path, and that nothing uses an owner once it has been.
It never releases anything by itself: what runs is what's written, and what's missing is an error (E4035).

```
File :: struct #owned(close_file) {
    handle : int,
}

close_file :: fn(file: File) {/* ... */}

main :: fn() {
    log :: open_file("log.txt")
    defer compiler.release(log)         // close_file(log), when main ends
    write_line(&log, "started")         // &log only borrows it
}
```

## Owners

The owner of an `#owned` value is the local or parameter holding it.

* **Moving.** Giving the value to another local, passing it by value, returning it, or storing it (through a pointer,
  in a struct or array literal, or with `array_add`) moves it: the owner can't be used again until it's given a new
  value. A function taking one by value owns it, and has to release it or move it on.
* **Borrowing.** Taking its address, reading its fields, comparing it, or giving it to an `any`, as `log_info` takes
  its values, leaves it where it is. A value given to an `#escaping` `any`, like a new thread's data, is moved.
* **Ending.** On every path out of a scope, its end, `return`, `break` or `continue`, each owner declared in it has
  been moved or released. A `defer` counts where it runs.
* **Paths that meet,** after an `if`, a `match` or a loop, have to agree: an owner moved on one and not the other is
  an error there. A loop can't move an owner from outside it unless it gives it a new value before going around.
* **Replacing** a value an owner still has is an error: release or move it first.
* **Dropping.** A call's owned result, or an owned literal, that nothing keeps is an error.
* **Zero owns nothing.** An owner declared without a value owns nothing until it's given one, or until its address is
  taken, since what it's given to may fill it, like `array_add(&files, file)`.

`#release` after an owner's name releases it where its scope ends, as `defer compiler.release(name)` written there
would. An owner marked `#release` can't be moved, since whether to release it would depend on the path taken:

```
consume :: fn(file #release : File) -> int {
    return file.handle
}                                       // released here

buffer #release :: make_buffer(4096)
```

## What Holds Owners

* **A struct holding an owned value** is owned too, and says so with `#owned`, with a function of its own that
  releases what it holds. An instance of a generic is owned when it holds one, like `Optional[File]`.
* **A dynamic array** holds its elements, so `File[..]` is owned. `runtime.array_release(files, close_file)` releases
  each element with the function given, then frees the array.
* **A view** borrows its elements: going through one, `for file in files^`, doesn't move them, and moving an element
  out of one, or out of a field, is an error.
* **Matching** an owned value that's made for it, like `match maybe_open(path) { case Some(file) => ... }`, gives the
  bindings ownership; matching an owner only borrows it.
* **`#owned(release, condition)`** decides per instance of a generic, like a container that's owned only when its
  elements are: `#owned(release_map, !compiler.satisfies(compiler.Copyable(V)))`.

Beyond locals and parameters, through pointers and on the heap, owners aren't tracked: what's stored there is the
responsibility of whatever owns that memory, which is itself an owner, as a dynamic array is.

## Making and Ending Owners

base/compiler has what a type's own functions use to work outside the rules, and what general code uses to release
any owner:

| Function | Does |
|---|---|
| `compiler.release(value)` | Calls the function `value`'s type names in `#owned(...)` |
| `compiler.take(&place)` | Moves out what a place holds, a field or an element, leaving it zero, which owns nothing |
| `compiler.forget(value)` | Ends an owner with nothing done: nothing releases what it held |
| `compiler.duplicate(&value)` | A second owner of the same value, without its type knowing, for a type's own share function |

## Shared Ownership

std/memory's `SharedPtr[T]` is a value on the heap with several owners, released when the last one is done with it.
It's `#owned`, so each owner is released or moved on like any other, and the compiler checks it:

```
buffer #release :: memory.make_shared(Buffer.{size = 4096}, destroy_buffer)
reader :: memory.share(&buffer)             // a second owner
spawn_reader(reader)                        // moved to the reader, which releases it
log_info("% bytes", buffer.size)            // the value's fields, through using
```

| Function | Does |
|---|---|
| `make_shared(value, destroy, allocator)` | Moves `value` into a new block with its counts, and gives its first owner |
| `share(&shared)` | Another owner of the same value |
| `release(shared)` | Drops an owner; the last one destroys the value and frees the block |
| `weaken(&shared)` | A `WeakPtr`, which doesn't keep the value |
| `upgrade(&weak)` | An owner, while there's still one, or null |
| `release_weak(weak)` | Drops a weak reference |
| `pointer_of(&shared)` | The value's address, for passing on |

* **One allocation.** A `SharedPtr` is one pointer, to the value, with its counts in a header just before it in the same
  block. Its field is named `shared_value`, and its members are the value's through `using`, so `shared.size` is the
  value's field, as long as the value has no field called `shared_value`.
* **What runs at the last release** is the `destroy` function `make_shared` was given, like closing a file, with the
  value's address. Without one, a value whose type is `#owned` is released with its own release function, so a shared
  file closes itself; anything else needs nothing. The function is kept in the block, not the type, so every
  `SharedPtr[File]` is one type whatever closes it.
* **Read-only and changeable.** `make_shared` gives a `SharedPtr[mut T]`, which can change the value; a
  `SharedPtr[T]` can only read it, and one becomes the other by itself (see
  [types.md](types.md#mutability-in-type-arguments)).
* **Threads.** Counting is atomic, so owners can be on different threads. `SharedPtr[T, false]`, or `LocalPtr[T]`,
  counts with plain arithmetic, for values that stay on one thread.
* **Weak references** keep the block, not the value: `upgrade` counts up only while some owner is left, and the block
  goes once the last owner and the last weak reference are both released.

## Generics

A generic's body is checked with each instance's own types, so an instance given an owned type that copies or drops
it is reported in that instance. `T: compiler.Copyable` says up front that a generic copies its `T`, so an owned
type is refused where the instance is made instead. In a body checked before any instance (see
[types.md](types.md#checked-bodies)), a type parameter is treated as copyable.

## Prior Art

* C#'s `ref struct`, `Span<T>` and `scoped`: local "safe-to-escape" rules, which `#scoped` structs are modeled on.
* Swift: closures don't escape unless marked `@escaping`, which `#escaping` is named after.
  Swift has since added non-escapable types and `Span`.
* D's `scope` parameters: a warning to keep the set of annotations small.
* Go's escape analysis: the same analysis, but Go moves escaping values to the heap instead of reporting them.
  Hemera's allocations are explicit, so it reports an error.

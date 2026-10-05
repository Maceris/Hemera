# Multitasking

There are two main types of multitasking in Hemera.
Regular (preemptive) operating system threads, and cooperatively scheduled fibers.

Code does not need to know which one it is running on. Every function is compiled once, and behaves the same on a
thread, on a fiber, or at compile time. There is no `async`/`await` and no other marking of functions that might
suspend: any function may call `fiber_yield()`, and whether that actually switches to other work is decided by
the runtime.

# Threads

When new threads are created, they are passed a function to start running,
and optionally some data that this function expects. The function will
then start running in a new thread.

The new thread starts with a copy of the creating thread's context (see [Contexts](#contexts)).

# Fibers

Fibers are cooperatively scheduled, with runtimes that share
tasks among one or more threads. The fiber runtimes can be user-defined,
though there is an implementation in the standard library.

A fiber is a function, some data, its own small stack, and its own root context. A scheduler runs fibers on one or
more OS threads, called *carriers*. A suspended fiber may be resumed on a different carrier than the one it was
suspended on.

The design goals are:

* Cheap yields and resumes, on the order of a function call or two.
* Many idle fibers: the target is a million suspended fibers in at most 1.5 GB of runtime overhead
  (about 1.5 KiB each), not counting what the program itself allocates per task.
* No function coloring, and a single compiled copy of every function.
* Working on systems that enforce hardware control-flow integrity: x86 CET shadow stacks,
  AArch64 Guarded Control Stacks (GCS), pointer authentication (PAC), and indirect branch tracking (IBT/BTI).

## Yielding

`fiber_yield()` means "now would be a good time to do other work". It is a hint, and the runtime is free to ignore
it and return immediately. It declines when:

* The carrier has no fiber scheduler (plain threads), or the code is running at compile time.
* There are foreign (C) frames on the current stack, see [Foreign Code](#foreign-code).
* The code is inside a no-yield region, see [Carriers](#carriers).
* The scheduler has nothing else worth running.

From the calling function's point of view, the only observable differences between a yield that switched and
one that didn't are that time passed, and that the code may be running on a different OS thread afterwards.

## Waiting

Waiting for something (I/O, a timer, a lock) can't rely on `fiber_yield()` alone, because a declined yield returns
immediately. Waiting goes through the scheduler's `park` operation instead: if the fiber can be suspended, it is
suspended until the waiter is woken. If it can't (for the same reasons a yield would decline), `park` reports that,
and the waiting code falls back to blocking the carrier thread.

Functions that wait look the same either way: `read(socket)` suspends the fiber when it can, and blocks the thread
when it can't.

## Stacks

Each fiber has its own stack, made of one or more segments. A fiber's stack never moves, so frames keep the same
address for their whole lifetime, across yields and across carriers.

* The first segment is part of the fiber's own allocation, see [Memory Budget](#memory-budget).
* Every function checks for stack overflow in its prologue, comparing the stack pointer against the current carrier's
  `stack_limit`. When a function needs more room than is left, it calls `morestack`, which runs the function
  on a new segment and switches back when it returns.
  Small leaf functions skip the check. The details are in [calling_convention.md](calling_convention.md).
* Segments come from a per-carrier cache, not directly from the OS, so there are no guard pages or memory mappings
  per fiber. The last segment a fiber left is kept as the carrier's spare, so a function call that keeps crossing
  a segment boundary in a loop doesn't allocate and free a segment each time.
* A suspended fiber only holds the segments its live frames are in.

Plain threads use the same prologue check: `stack_limit` is the thread's stack limit, and running out of stack is
a deterministic error rather than a fault on a guard page.

Since frames never move, pointers to stack variables stay valid across yields, even when a fiber moves to
another OS thread. The compiler checks that they can't outlive the frame they point into,
see [memory.md](memory.md#pointers-to-the-stack).

## Suspending and Resuming

Suspending a fiber saves its callee-saved registers on its own stack, records where its innermost frame continues,
and switches back to the scheduler. Nothing is copied.

Resuming does not jump straight back into the suspended frames. Instead, a small runtime loop re-enters the
innermost frame with a real `call`, and when that frame returns to the loop, it re-enters the next frame out the
same way, and so on. Frames that the fiber resumes and then returns from normally never come back to the loop.

Re-entering with a real `call` means every `ret` goes to an address that a matching `call` pushed, which is what
shadow stacks check, and return addresses never need to be rewritten. This works with only the carrier thread's own
shadow stack, so fibers don't need a shadow stack each.

Yielding costs O(1). Resuming costs O(1), plus one pass through the loop for each suspended frame that returns.
The protocol is described in [calling_convention.md](calling_convention.md#suspending-and-resuming-a-fiber).

## Foreign Code

Foreign functions (C, and anything else using the platform's convention) can't run on a fiber's small segments,
and can't be suspended, since their frames may hold anything.

* A call to a foreign function switches to the carrier thread's own stack first, and increments the carrier's
  `foreign_depth`. Both are undone when the call returns.
* If foreign code calls back into Hemera, the callback runs on the carrier's stack, and any yield inside it declines
  because `foreign_depth > 0`. Waiting inside a callback blocks the carrier.
* If foreign code blocks, the carrier is blocked too. Schedulers may add carriers to make up for that.

## Signals

The runtime installs its signal handlers to run on an alternate signal stack for each carrier, since a signal
delivered on a fiber's small segment could overflow it. Signal handlers installed by foreign libraries without
an alternate stack can overflow a fiber's stack, the same as in Go.

# Contexts

The context follows the logical call chain, not the OS thread: it is what the caller set up, and it can only be
changed for a scope, with `push_context` (see [control_flow.md](control_flow.md#push-context)).
Functions can't modify the context they were given.

* Threads and fibers each get a root context, copied by value from the context of whoever created them.
  A fiber's root context lives in the fiber's own allocation.
* A pushed context lives in the frame that pushed it. Frames never move, so it stays valid
  while its block runs, whichever carrier that happens on.
* What a context *points to* (the allocator's data, the logger, the random number generator) is shared by every
  thread and fiber that inherited it, and fibers can run on several carriers at once. Anything reachable from a
  context given to a new thread or fiber must be thread-safe, or owned by that thread or fiber.
  A non-thread-safe temporary allocator is the usual mistake.
* The context doesn't contain anything about where the code is running (which OS thread, which scheduler).
  That changes underneath a fiber when it moves between carriers, so it lives in the carrier block instead.

## Assertion Handlers

`context.assertion_handler` is inherited like the rest of the context, so every thread and fiber created from
the same context shares one handler:

* Handlers must be thread-safe, since several threads or fibers can fail at once.
* `assert` calls the handler inside a no-yield region, so the failing fiber isn't suspended while its handler runs,
  and no other fiber runs on that carrier in the meantime. A handler that waits (writing a log over the network,
  say) blocks its carrier, which is acceptable for a program that is about to stop.
* An assertion that fails inside a handler traps immediately, instead of calling the handler again.
* Handlers end the whole program, not just the failing fiber. Ending only the fiber would skip its `defer`
  statements and could leave locks held for other fibers.

# Carriers

Every OS thread that runs Hemera code has a carrier block: a small, runtime-owned structure describing the current
execution environment. It holds:

* `stack_limit`, read by every function prologue
* the current stack segment, and a spare
* `foreign_depth` and `no_yield_depth`
* the current fiber, the scheduler's yield function and data, if a scheduler is running on this thread
* bookkeeping for switching between the scheduler and fibers
* the carrier's index

Hemera code keeps a pointer to the carrier block in a register that is never used for anything else
(`r14` on x86-64, `x28` on AArch64). Both platform conventions preserve those registers, so foreign code leaves it
alone. It is loaded from the OS's thread-local storage only at the boundaries: when a thread starts, and when foreign
code calls back into Hemera. Fiber switches never save or restore it, so a resumed fiber always sees the carrier
it is actually running on.

This isn't a mutable global variable in the language's sense. User code can't name it, and the language's
semantics don't depend on it. It is per-thread execution state, in the same category as the stack pointer or the
stack itself. Per-call-chain state, like an allocator, belongs in the context.

`base` and `std` code can get at the carrier block with `intrinsics.carrier()`. Since any call might yield and
move the fiber to another carrier, a carrier pointer is only valid until the next call that could yield. Code that
needs per-carrier state (allocator caches, run queues) does it inside a no-yield region:

```
runtime.no_yield_enter()
defer runtime.no_yield_exit()
// fiber_yield() declines in here, so this is still the same carrier
```

`runtime.current_thread_index()` gives the index of the carrier running the caller. It can be different after any
call that might yield.

# Memory Budget

The target is 1.5 GB of runtime overhead for a million idle fibers, or 1536 bytes each. Each fiber is a single
allocation of `FIBER_BLOCK_SIZE` bytes, which is calculated from its parts:

| Part                                                         | Constant                   | Approximate size |
|--------------------------------------------------------------|----------------------------|------------------|
| Fiber struct: state, resume state, links, and root context   | `size_of(Fiber)`           | 176 bytes        |
| Stack guard                                                  | `STACK_GUARD`              | 256 bytes        |
| Usable stack in the first segment                            | `FIBER_INITIAL_STACK_SIZE` | 1024 bytes       |
| Total                                                        | `FIBER_BLOCK_SIZE`         | 1456 bytes       |

That leaves about 80 bytes of each fiber's share of the budget for the allocator's own overhead.

While suspended, the fiber's callee-saved registers are on its stack:
about 40 bytes for x86-64 System V, 216 bytes for x86-64 Windows (which includes `xmm6`-`xmm15`), and 144 bytes
for AArch64.

A fiber that suspends with its frames inside the first segment costs exactly the block. One that suspends deeper
holds another segment (`STACK_SEGMENT_SIZE`, 1 KiB by default) for each segment its frames reach into.
So the budget holds as long as typical waits happen with about a kilobyte of frames on the stack, which is
something to measure on real servers. The sizes are constants in `base/runtime/fiber.hsc`.

Not included are the scheduler's queues, and whatever the program allocates per task.

# Compile Time

At compile time the compiler may run fibers however it likes (fake threads, running them to completion one at a
time), and `fiber_yield()` may do nothing. Functions see the same interface either way.

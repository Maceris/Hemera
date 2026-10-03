# Multitasking

There are two main types of multitasking in Hemera. 
Regular (preemptive) operating system threads, and cooperatively scheduled fibers.

# Threads

When new threads are created, they are passed a function to start running,
and optionally some data that this function expects. The function will
then start running in a new thread.

# Fibers

Fibers are cooperatively scheduled, with runtimes that share
tasks among one or more threads. The fiber runtimes can be user-defined,
though there is an implementation in the standard library.

The context has a couple fields related to fibers:

* is_running_on_a_fiber should be set to true by the runtime once it starts running
* fiber_yield_function is a function that, if present, is what we should call when anyone within that thread calls fiber_yield().
* fiber_data stores (fiber runtime) implementation-defined data

The standard implementation involves sharing fibers among any threads
started using the same scheduler. Fibers are essentially a function and some data,
and the scheduler running them essentially just calls the function. 

If any fiber yields, however, the whole stack (between the fiber scheduler and the yield) is frozen
(copied to heap memory, cleared off the stack) and a different fiber takes over on that thread.
When it's time to resume a fiber, a single stack frame is thawed onto the current stack,
rather than the whole frozen stack, to avoid repeated large memory copies when fibers
may be repeatedly yielding in a tight loop.

The fact that any function anywhere could have its stack moved around, because something
yielded, is the main reason why we don't allow any pointers to anything on the stack.

The other main reason is that not having any pointers to the stack makes it
much harder to accidentally mess up the stack, you have to go way out of your way to call
specific primitives to get/change the stack.

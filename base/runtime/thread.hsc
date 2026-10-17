package runtime

// A thread's data came through thread_create's #escaping data, so it never points into a stack
ThreadFunction :: fn(data #escaping : any) -> void

// Windows' is in windows.hsc
#if OS == .Mac {
    ThreadSpecificOS :: struct {

    }
}
#else_if OS == .Linux && TARGET_ARCH != .x86_64 {
    ThreadSpecificOS :: struct {

    }
}
#else_if OS == .None {
    ThreadSpecificOS :: struct {

    }
}
#else_if OS == .SlopOS {
    ThreadSpecificOS :: struct {

    }
}
#else_if OS == .UEFI {
    ThreadSpecificOS :: struct {

    }
}

// How a thread's stack is set up, see docs/multitasking.md (Stacks).
ThreadStack :: union {
    // Hemera code runs on segments, which grow as needed. The default.
    Segmented(SegmentedStack),
    // One fixed stack of this many bytes. Running out of it is an error.
    Fixed(usize),
}

SegmentedStack :: struct {
    // Size of the first segment, allocated with the thread.
    first_segment : usize = 1024,
    /*
     * Size of the native stack for foreign calls, on systems that don't give every thread a stack.
     * It's allocated on the thread's first foreign call. Ignored where the system provides one.
     */
    native_stack : usize = 65536,
}

DEFAULT_THREAD_STACK : ThreadStack : .Segmented(SegmentedStack.{})

Thread :: struct {
    // The thread's carrier block, from when it starts until it's joined
    carrier : CarrierBlock,
    // For the thread's carrier block, which code on the thread can read with current_thread_index
    index : usize,
    stack : ThreadStack,
    function : ThreadFunction,
    data : any?,
    // A copy of the creating thread's context, which the new thread starts with
    starting_context : Context,
    // starting_context's own copy of its extension chain
    extensions : ContextExtension[],
    using ThreadSpecificOS,
}

// data is kept until the thread runs, so it can't point into the caller's stack
thread_create :: fn(
    function: ThreadFunction,
    data #escaping : any? = null,
    stack := DEFAULT_THREAD_STACK,
) -> ptr[mut Thread] {
    result : ptr[mut Thread] = new(Thread)
    result.carrier = CarrierBlock.{}
    result.stack = stack
    result.function = function
    result.data = data
    result.starting_context = context
    extensions, error :: copy_extensions(&result.starting_context)
    assert(error == null, "out of memory copying the context's extensions for a new thread")
    result.extensions = extensions

    return result
}

/*
 * Start running the thread: its entry loads the carrier register with the thread's carrier block,
 * sets stack_limit and native_stack_limit from its own stack, and calls function(data) with
 * starting_context. False if the system couldn't start it.
 *
 * Not yet: storing the carrier block in the OS's thread-local storage, for callbacks from foreign
 * code, and running a thread's Hemera code on segments rather than the stack the system gives it.
 */
thread_start :: fn(thread #escaping : ptr[mut Thread]) -> bool {
    thread.carrier.index = thread.index
    return os_thread_start(thread)
}

// Wait for the thread to finish, then free it, with the allocator that was current when it was made.
thread_join :: fn(thread: ptr[mut Thread], allocator := context.allocator, loc := #caller_location) {
    os_thread_join(thread)
    free_array(thread.extensions, allocator, loc)
    free(thread, allocator, loc)
}

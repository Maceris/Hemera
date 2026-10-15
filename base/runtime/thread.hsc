package runtime

ThreadFunction :: fn(any) -> void

#if OS == .Windows {
    ThreadSpecificOS :: struct {

    }
}
#else_if OS == .Mac {
    ThreadSpecificOS :: struct {

    }
}
#else_if OS == .Linux {
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
#else {
    //TODO(ches) error, unsupported
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
) -> ptr[Thread] {
    result : ptr[mut Thread] = new(Thread)
    result.stack = stack
    result.function = function
    result.data = data
    result.starting_context = context
    extensions, error :: copy_extensions(&result.starting_context)
    assert(error == null, "out of memory copying the context's extensions for a new thread")
    result.extensions = extensions

    return result
}

thread_start :: fn(thread: ptr[Thread]) {
    todo("start running the thread")
    /*
     * The new thread's entry needs to, before running any Hemera code:
     * allocate its CarrierBlock, store the pointer in the OS's thread-local storage,
     * load the carrier register, and set stack_limit and native_stack_limit from the
     * thread's stack bounds. Then call function(data) with starting_context.
     */
}

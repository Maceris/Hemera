package runtime

/**
 * What a thread or a fiber runs.
 *
 * Its data comes through thread_create's or fiber_create's #escaping data, so it never points into a stack; an empty
 * any (a null type) when none was given.
 */
ThreadFunction :: fn(data #escaping : any) -> void

// Windows' is in windows.hsc, and SlopOS's in slop_os_threads.hsc
#if OS == .Mac {
    /** A thread's system-specific state, which Thread includes: none, since threads don't start here yet. */
    ThreadSpecificOS :: struct {

    }
}
#else_if OS == .Linux && TARGET_ARCH != .x86_64 && TARGET_ARCH != .arm64 {
    /** A thread's system-specific state, which Thread includes: none, since threads don't start here yet. */
    ThreadSpecificOS :: struct {

    }
}
#else_if OS == .None {
    /** A thread's system-specific state, which Thread includes: none, without an operating system. */
    ThreadSpecificOS :: struct {

    }
}
#else_if OS == .UEFI {
    /** A thread's system-specific state, which Thread includes: none, since UEFI has no threads to start. */
    ThreadSpecificOS :: struct {

    }
}

/** How a thread's stack is set up, see docs/multitasking.md (Stacks). */
ThreadStack :: union {
    /** Hemera code runs on segments, which grow as needed. The default. */
    Segmented(SegmentedStack),
    /** One fixed stack of this many bytes. Running out of it is an error. */
    Fixed(usize),
}

/** How a segmented stack starts: the sizes of its first segment and of its native stack for foreign calls. */
SegmentedStack :: struct {
    /** The size in bytes of the first segment, allocated with the thread. */
    first_segment : usize = 1024,
    /**
     * The size in bytes of the native stack for foreign calls, on systems that don't give every thread a stack.
     * It's allocated on the thread's first foreign call. Ignored where the system provides one.
     */
    native_stack : usize = 65536,
}

/** The stack a thread gets unless thread_create is given another: segmented, with SegmentedStack's defaults. */
DEFAULT_THREAD_STACK : ThreadStack : .Segmented(SegmentedStack.{})

/**
 * A thread, from thread_create until thread_join frees it.
 *
 * The thread's carrier block is part of it, so the Thread has to stay where it is while the thread runs.
 */
Thread :: struct {
    /** The thread's carrier block, from when it starts until it's joined. */
    carrier : CarrierBlock,
    /**
     * The index thread_start gives the thread's carrier block, which code on the thread can read with
     * current_thread_index; 0 unless the caller sets it before thread_start.
     */
    index : usize,
    /** How the thread's stack is set up, from thread_create. */
    stack : ThreadStack,
    /** What the thread runs, given data. */
    function : ThreadFunction,
    /** What function is given, or null for none. */
    data : any?,
    /** A copy of the creating thread's context, which the new thread starts with. */
    starting_context : Context,
    /** starting_context's own copy of its extension chain, from copy_extensions, freed by thread_join. */
    extensions : ContextExtension[],
    // What the operating system keeps for the thread, like its handle
    using ThreadSpecificOS,
}

/**
 * Make a thread that will run function(data), starting with a copy of the current context.
 *
 * Nothing runs until thread_start. The Thread and its copy of the context's extension chain come from the context's
 * allocator, which has to be the one given to thread_join. Without the memory for either, calls
 * context.assertion_handler, which ends the program.
 *
 * @param function What the thread runs.
 * @param data What function is given, or null for nothing. It's kept until the thread runs, on another thread, so
 *     it can't point into the caller's stack.
 * @param stack How the thread's stack is set up.
 * @return The new thread, owned by the caller until thread_join frees it; never null.
 */
thread_create :: fn(
    function: ThreadFunction,
    data #escaping #crosses_threads : any? = null,
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

/**
 * Start running the thread: its entry loads the carrier register with the thread's carrier block,
 * sets stack_limit and native_stack_limit from its own stack, and calls function(data) with
 * starting_context.
 *
 * Not yet: storing the carrier block in the OS's thread-local storage, for callbacks from foreign
 * code, and running a thread's Hemera code on segments rather than the stack the system gives it.
 *
 * @param thread The thread, from thread_create, not started before. Its index is copied into its carrier block
 *     first. The running thread uses it until it's joined, so it has to stay valid until thread_join.
 * @return True once the thread is started; false if the system couldn't start it, or can't start threads at all,
 *     and then it never runs.
 */
thread_start :: fn(thread #escaping : ptr[mut Thread]) -> bool {
    thread.carrier.index = thread.index
    return os_thread_start(thread)
}

/**
 * Wait for the thread to finish, then free it.
 *
 * @param thread The thread, from thread_create; it's freed, and with it its carrier block, so nothing may use it
 *     after this.
 * @param allocator The allocator that was current when thread_create made it.
 * @param loc The caller's location, given to the allocator.
 */
thread_join :: fn(thread: ptr[mut Thread], allocator := context.allocator, loc := #caller_location) {
    os_thread_join(thread)
    free_array(thread.extensions, allocator, loc)
    free(thread, allocator, loc)
}

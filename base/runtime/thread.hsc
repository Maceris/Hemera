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

Thread :: struct {
    index : usize,
    function : ThreadFunction,
    data : any?,
    // A copy of the creating thread's context, which the new thread starts with
    starting_context : Context,
    using ThreadSpecificOS,
}

// data is kept until the thread runs, so it can't point into the caller's stack
thread_create :: fn(function: ThreadFunction, data #escaping : any? = null) -> ptr[Thread] {
    result : ptr[Thread] = new(Thread)
    result.function = function
    result.data = data
    result.starting_context = context

    return result
}

thread_start :: fn(thread: ptr[Thread]) {
    //TODO(ches) start running the thread
    /*
     * The new thread's entry needs to, before running any Hemera code:
     * allocate its CarrierBlock, store the pointer in the OS's thread-local storage,
     * load the carrier register, and set stack_limit and native_stack_limit from the
     * thread's stack bounds. Then call function(data) with starting_context.
     */
}

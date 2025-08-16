package runtime

ThreadIndex :: alias u32
ThreadFunction :: fn(any) -> void

#if OS == .Windows {
    ThreadSpecificOS :: struct {

    }
}
#elif OS == .Mac {
    ThreadSpecificOS :: struct {

    }
}
#elif OS == .Linux {
    ThreadSpecificOS :: struct {

    }
}
#else {
    //TODO(ches) error, unsupported
}

Thread :: struct {
    index : ThreadIndex,
    function : ThreadFunction,
    data : any,
    starting_context : Context,
    using ThreadSpecificOS,
}

thread_create :: fn(function: ThreadFunction, data: any = null) -> ptr[Thread] {
    result : ptr[Thread] = new(Thread)
    result.function = function
    result.data = data
    result.starting_context = context

    return result
}

thread_start :: fn(thread: ptr[Thread]) {
    //TODO(ches) start running the thread
}

fiber_yield :: fn() {
    //TODO(ches) I would like this to be a macro
    yield_function :: context.fiber_yield_function or_return
    yield_function()
}

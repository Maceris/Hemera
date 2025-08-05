package runtime

ThreadIndex :: alias u32
ThreadFunction :: fn(rawptr) -> void

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
    data : rawptr,
    starting_context : Context,
    using ThreadSpecificOS,
}

thread_create :: fn(function: ThreadFunction, data: rawptr = null) -> ptr[Thread] {
    result : ptr[Thread] = new(Thread)
    result.function = function
    result.data = data
    result.starting_context = context

    return result
}

thread_start(thread: ptr[Thread]) {
    //TODO(ches) start running the thread
}

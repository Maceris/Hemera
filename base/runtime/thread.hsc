package runtime

ThreadIndex :: alias u32
ThreadFunction :: fn(rawptr) -> void

Thread :: struct {
    index : ThreadIndex,
    function : ThreadFunction,
    data : rawptr,
    starting_context : Context,
    //TODO(ches) using OS-specific thread info
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

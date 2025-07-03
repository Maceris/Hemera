package concurrency

FutureState :: enum {
    NotStarted,
    Running,
    Completed,
}

Future :: struct[T] {
    result: T,
    input: any,
    function: fn(any) -> void,
    state: FutureState,
}

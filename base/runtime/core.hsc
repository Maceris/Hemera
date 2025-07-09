package runtime

Allocator :: struct {
    function : AllocatorFn,
    data : rawptr,
}

AllocatorFn :: alias fn(
    allocator_data: rawptr,
    size: int,
    alignment: int,
    old_memory: rawptr,
    old_size: int,
    location:= #caller_location
    )-> (u8[], AllocatorError?)

AllocatorError :: enum #backed_by(u8) {
    OutOfMemory,
    InvalidPointer,
    InvalidArgument,
}

Optional :: union[T] {
    Some(T),
    None,
}

SourceCodeLocation :: struct {
    file_path: string,
    function: string,
    line: u32,
    column: u16,
}

Result :: union[T, E] {
    Ok(T),
    Error(E),
}

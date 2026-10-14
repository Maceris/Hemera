package runtime

Allocator :: struct {
    function : AllocatorFn,
    data : rawptr,
}

AllocatorFn :: alias fn(
    allocator_data: rawptr,
    size: usize,
    alignment: int,
    old_memory: rawptr,
    old_size: usize,
    location:= #caller_location
    )-> (u8[], AllocatorError?)

AllocatorError :: enum #backed_by(u8) {
    OutOfMemory,
    InvalidPointer,
    InvalidArgument,
}

SourceCodeLocation :: struct {
    file_path: string,
    function: string,
    line: u32,
    column: u16,
}

package runtime

// #unrestricted: what's allocated through one can be kept anywhere (docs/memory.md, Unrestricted Structs)
Allocator :: struct #unrestricted {
    function : AllocatorFn,
    data : rawptr,
}

AllocatorFn :: alias fn(
    allocator_data: rawptr,
    size: usize,
    alignment: usize,
    old_memory: rawptr,
    old_size: usize,
    location:= #caller_location
    )-> (u8[], AllocatorError?)

AllocatorError :: enum #backed_by(u8) {
    OutOfMemory,
    InvalidPointer,
    InvalidArgument,
}

SourceCodeLocation :: struct #unrestricted {
    file_path: string,
    function: string,
    line: u32,
    column: u16,
}

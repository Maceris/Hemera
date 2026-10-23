package runtime

// #unrestricted: what's allocated through one can be kept anywhere (docs/memory.md, Unrestricted Structs)
Allocator :: struct #unrestricted {
    function : AllocatorFn,
    data : rawptr,
}

/*
 * Allocates, frees or resizes a block (docs/memory.md, Allocators). With old_memory null, a new block of size
 * bytes aligned to alignment; with size 0, frees old_memory; with both, resizes it, keeping its alignment. Freeing
 * and resizing pass the block's old_size and alignment as it was allocated, so an allocator can find a block from
 * them.
 */
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

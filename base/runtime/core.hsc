package runtime

/**
 * An allocator: a function that allocates, frees and resizes blocks, and the state it works on (docs/memory.md,
 * Allocators).
 *
 * It's #unrestricted, so what's allocated through one can be kept anywhere (docs/memory.md, Unrestricted Structs).
 * It's two words, passed by value; copies of it are the same allocator.
 */
Allocator :: struct #unrestricted {
    /** What does the work; null in an Allocator that's never been set, as a dynamic array's starts. */
    function : AllocatorFn,
    /** The allocator's state, passed to function as allocator_data each call; null for one that keeps none. */
    data : rawptr,
}

/**
 * Allocate, free or resize a block (docs/memory.md, Allocators).
 *
 * With old_memory null, a new block of size bytes aligned to alignment; with size 0, frees old_memory; with both,
 * resizes it, keeping its alignment. Freeing and resizing pass the block's old_size and alignment as it was
 * allocated, so an allocator can find a block from them. A new block is zeroed.
 *
 * @param allocator_data The Allocator's data: its state, which only it knows the type of.
 * @param size The size wanted, in bytes; 0 to free.
 * @param alignment The block's alignment in bytes, a power of two: the one asked for a new block, and the one it was
 *     allocated with when it's freed or resized.
 * @param old_memory The block to free or resize, which this allocator gave, or null for a new block.
 * @param old_size old_memory's size in bytes, as it was allocated or last resized; 0 for a new block.
 * @param location Where the call was made, for an allocator that tracks or reports it; the caller's own by default.
 * @return The block, size bytes long, owned by the caller until it's freed. Empty when freeing, or on an error.
 * @return Null on success, or why it failed: OutOfMemory without the memory, InvalidArgument for an alignment
 *     that isn't a power of two, or InvalidPointer for an old_memory it didn't give. On an error a resized block is
 *     left as it was.
 */
AllocatorFn :: alias fn(
    allocator_data: rawptr,
    size: usize,
    alignment: usize,
    old_memory: rawptr,
    old_size: usize,
    location:= #caller_location
    )-> (mut u8[], AllocatorError?)

/** Why an allocator couldn't do what it was asked. */
AllocatorError :: enum #backed_by(u8) {
    /** There wasn't the memory: the allocator, or what it gets memory from, had no block that size free. */
    OutOfMemory,
    /** The block to free or resize isn't one the allocator gave. */
    InvalidPointer,
    /** Something else asked isn't possible, like an alignment that isn't a power of two. */
    InvalidArgument,
}

/**
 * A place in the program's source, as #caller_location gives it, which assertion handlers, loggers and allocators
 * report. #unrestricted, since its strings are constants that last as long as the program.
 */
SourceCodeLocation :: struct #unrestricted {
    /**
     * The file's path: base's files as <base>/..., std's as <std>/..., and every other relative to the folder of the
     * package being built, with / throughout (docs/compilation.md).
     */
    file_path: string,
    /** The name of the function the place is in. */
    function: string,
    /** The line in the file. */
    line: u32,
    /** The column on the line. */
    column: u16,
}

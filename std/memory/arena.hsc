package memory

import intrinsics from "base"
import runtime from "base"

/**
 * An arena: a bump allocator over chunks it takes from another allocator, for memory that's all given back at once.
 *
 * It suits what a frame or a request builds and drops. Allocating moves a chunk's offset on; freeing gives back only
 * the newest block, so temporaries made and freed in turn unwind, and anything else stays until the arena is reset,
 * restored to a mark, or freed. Blocks are zeroed, as other allocators' are.
 *
 *     frame :: memory.make_arena() or_return 1
 *     defer memory.free_arena(frame)
 *     info := memory.new_value(Info.{count = 3}, memory.arena_allocator(frame))
 *     // ...
 *     memory.reset_arena(frame)       // everything from it is gone; its first chunk is kept for next time
 *
 * Memory from an arena is like any allocator's: pointers to it can be kept in structs, dynamic arrays and the heap,
 * unlike pointers into the stack (docs/memory.md, Pointers to the Stack), and they're valid until the arena gives it
 * back. An arena isn't for sharing: one thread uses it at a time, since nothing in it is atomic or locked.
 */
Arena :: struct {
    /** The allocator chunks, and the arena itself, are taken from and given back to. */
    backing : runtime.Allocator,
    /**
     * The size of each chunk taken from backing, in bytes, header included; a larger block gets a chunk of its own
     * size. Always more than ARENA_CHUNK_HEADER.
     */
    chunk_size : usize,
    /** The newest chunk, which blocks come from, holding the one before it; null until the first allocation. */
    current : ptr[mut ArenaChunk]?,
    /** The newest block's address, which freeing gives back and resizing grows in place, or 0 when there's none. */
    last : usize,
}

/** A chunk of an arena: this header, then the bytes blocks are taken from. */
ArenaChunk :: struct {
    /** The chunk taken before this one, or null for the arena's first. */
    previous : ptr[mut ArenaChunk]?,
    /** Bytes after the header, which blocks can be taken from. */
    capacity : usize,
    /** Bytes after the header given out so far, alignment padding included; at most capacity. */
    used : usize,
}

/** Where an arena was, for arena_restore to go back to. Its zero value marks an arena without a chunk. */
ArenaMark :: struct {
    /** The arena's newest chunk when the mark was taken, or null if it had none. */
    chunk : ptr[mut ArenaChunk]?,
    /** How many of that chunk's bytes were used then. */
    used : usize,
}

/**
 * The size of the header before each chunk's bytes, in bytes, kept a multiple of 16 so blocks of up to 16-byte
 * alignment pack from the start.
 */
ARENA_CHUNK_HEADER :: (size_of(ArenaChunk) + 15) & ~cast[usize](15)

/** The chunk size make_arena uses when none is given, or when the one given is too small: 64 KiB, header included. */
ARENA_DEFAULT_CHUNK_SIZE : usize : 64 * 1024

/**
 * Make an arena that takes its chunks from backing.
 *
 * The arena is made with backing too, since the allocator it is holds it (arena_allocator). It takes no chunk until
 * something is allocated.
 *
 * @param chunk_size The size of each chunk taken from backing, in bytes, the chunk's header included. A size no larger
 *     than ARENA_CHUNK_HEADER, so with no room for blocks, is replaced with ARENA_DEFAULT_CHUNK_SIZE. A block too big
 *     for a chunk of this size gets a chunk of its own.
 * @param backing The allocator the arena and its chunks come from, which must outlive the arena.
 * @return The arena, owned by the caller, who gives it back with free_arena; or null if backing has no memory for it.
 */
make_arena :: fn(chunk_size := ARENA_DEFAULT_CHUNK_SIZE, backing := context.allocator) -> ptr[mut Arena]? {
    made, error :: runtime.new_aligned(Arena, align_of(Arena), backing)
    if error != null {
        return null
    }
    made^ = Arena.{backing = backing, chunk_size = if chunk_size > ARENA_CHUNK_HEADER { chunk_size } else { ARENA_DEFAULT_CHUNK_SIZE }}
    return made
}

/**
 * Give back every chunk and the arena itself to the backing allocator.
 *
 * @param arena An arena from make_arena. It, and every block allocated from it, is invalid afterwards.
 */
free_arena :: fn(arena: ptr[mut Arena]) {
    arena_free_chunks(arena, null)
    runtime.free_aligned(arena, align_of(Arena), arena.backing)
}

/**
 * Make the allocator an Arena is, for context.allocator or anything that takes one.
 *
 * @param arena The arena it allocates from, which must outlive the allocator and everything holding it.
 * @return An allocator whose blocks come from arena. Freeing through it gives back only the newest block; resizing
 *     the newest block grows or shrinks it in place when its chunk has room. A misaligned request (an alignment that
 *     isn't a power of two) fails with InvalidArgument, and a chunk backing can't give fails with OutOfMemory.
 */
arena_allocator :: fn(arena #escaping : ptr[mut Arena]) -> runtime.Allocator {
    return runtime.Allocator.{arena_function, cast[rawptr](arena)}
}

/**
 * Give back everything allocated from the arena, keeping its first chunk to allocate from again.
 *
 * The other chunks go back to the backing allocator, so an arena that grew for one large frame shrinks again.
 *
 * @param arena The arena. Every block allocated from it is invalid afterwards, and every mark taken of it is spent.
 */
reset_arena :: fn(arena: ptr[mut Arena]) {
    arena.last = 0
    first := arena.current
    loop {
        chunk :: first or_break
        previous :: chunk.previous or_break
        first = previous
    }
    arena_free_chunks(arena, first)
    chunk :: first or_return void
    chunk.used = 0
}

/**
 * Take a mark of where the arena is now, to give back what's allocated after it with arena_restore.
 *
 * @param arena The arena, which isn't changed.
 * @return The mark: the newest chunk and how much of it is used, or the zero ArenaMark if the arena has no chunk yet.
 */
arena_mark :: fn(arena: ptr[Arena]) -> ArenaMark {
    chunk :: arena.current or_return ArenaMark.{}
    return ArenaMark.{chunk = chunk, used = chunk.used}
}

/**
 * Give back everything allocated since a mark was taken, with the chunks taken since.
 *
 * Where the arena already gave back what the mark covers, by a reset or by restoring an earlier mark, there's nothing
 * more to give back, and it's left as it is.
 *
 * @param arena The arena the mark was taken of. Blocks allocated from it after the mark are invalid afterwards.
 * @param mark A mark from arena_mark on this arena. A mark taken before the arena had a chunk gives back every chunk.
 */
arena_restore :: fn(arena: ptr[mut Arena], mark: ArenaMark) {
    if !arena_after(arena, mark) {
        return void
    }
    arena.last = 0
    arena_free_chunks(arena, mark.chunk)
    chunk :: mark.chunk or_return void
    chunk.used = mark.used
}

/**
 * Tell whether the arena is past a mark, so restoring it has something to give back.
 *
 * @param arena The arena, which isn't changed.
 * @param mark A mark taken of it.
 * @return True if mark's chunk is still one of the arena's chunks, with no less of it used than then, or if mark was
 *     taken before the arena had a chunk; false once a reset or an earlier restore gave back what it covers.
 */
arena_after :: fn(arena: ptr[Arena], mark: ArenaMark) -> bool {
    marked :: mark.chunk or_return true
    next := arena.current
    loop {
        chunk :: next or_break
        if chunk == marked {
            return chunk != arena.current || chunk.used >= mark.used
        }
        next = chunk.previous
    }
    return false
}

/**
 * Count the bytes the arena has given out and not given back, across its chunks.
 *
 * @param arena The arena, which isn't changed.
 * @return The bytes used in all its chunks, alignment padding included, so possibly more than the blocks' sizes add up
 *     to; 0 for an arena without a chunk or just reset.
 */
arena_used :: fn(arena: ptr[Arena]) -> usize {
    total : usize = 0
    next := arena.current
    loop {
        chunk :: next or_break
        total += chunk.used
        next = chunk.previous
    }
    return total
}

/**
 * Allocate a new T holding a value, like a literal with some of its fields given: runtime.new, then the value stored.
 *
 * @tparam T The type to allocate.
 * @param value What the new T holds, copied in.
 * @param allocator Where the T comes from; the caller owns it and frees it with the same allocator.
 * @param loc Where the call is, for the allocator and for the report if allocation fails.
 * @return The new T, never null: if it can't be allocated, context.assertion_handler is called, as runtime.new does.
 */
new_value :: fn[T](value #escaping : T, allocator := context.allocator, loc := #caller_location) -> ptr[mut T] {
    made :: runtime.new(T, allocator, loc)
    made^ = value
    return made
}

/**
 * Give back the chunks newer than keep to the backing allocator, leaving keep the newest.
 *
 * @param arena An arena from make_arena, not yet freed; each chunk given back leaves its list, and
 *     blocks in them are no longer valid.
 * @param keep The chunk to stop at, kept with everything older; null gives back all of them. A chunk that isn't the
 *     arena's gives back all of them too.
 */
arena_free_chunks :: fn(arena: ptr[mut Arena], keep: ptr[mut ArenaChunk]?) {
    loop {
        chunk :: arena.current or_break
        if chunk == keep {
            break
        }
        arena.current = chunk.previous
        size :: ARENA_CHUNK_HEADER + chunk.capacity
        _, _ = arena.backing.function(arena.backing.data, 0, 16, cast[rawptr](chunk), size)
    }
}

/**
 * Take a block from the newest chunk, if it has room.
 *
 * @param arena An arena from make_arena, not yet freed; when a block is taken, its newest chunk's
 *     used grows by the block and its padding.
 * @param size The block's size in bytes.
 * @param align The block's alignment in bytes: a power of two, at least 1.
 * @return The block, zeroed, or null if the arena has no chunk or its newest has no room, in which case nothing
 *     changes.
 */
arena_take_from_newest :: fn(arena: ptr[mut Arena], size: usize, align: usize) -> rawptr {
    chunk :: arena.current or_return null
    start :: arena_chunk_start(chunk)
    at :: (start + chunk.used + align - 1) & ~(align - 1)
    offset :: at - start
    if offset > chunk.capacity || size > chunk.capacity - offset {
        return null
    }
    chunk.used = offset + size
    intrinsics.mem_zero(cast[mut rawptr](at), size)
    return cast[rawptr](at)
}

/**
 * Give back the newest block, rewinding its chunk to where the block started.
 *
 * @param arena An arena from make_arena whose newest block is block; its last is cleared and its
 *     newest chunk's used rewound.
 * @param block The newest block, which must be in the newest chunk. Afterwards the arena has no newest block, so a
 *     further free gives nothing back until something is allocated.
 */
arena_give_back_newest :: fn(arena: ptr[mut Arena], block: rawptr) {
    arena.last = 0
    chunk :: arena.current or_return void
    chunk.used = cast[usize](block) - arena_chunk_start(chunk)
}

/**
 * Resize the newest block where it is, zeroing any bytes it grows by.
 *
 * @param arena An arena from make_arena whose newest block is block; on success its newest chunk's
 *     used moves to the block's new end.
 * @param block The newest block, which must be in the newest chunk.
 * @param old_size The block's size now, in bytes.
 * @param size Its new size, in bytes.
 * @return True if it was resized; false if its chunk has no room, leaving it unchanged.
 */
arena_resize_newest :: fn(arena: ptr[mut Arena], block: rawptr, old_size: usize, size: usize) -> bool {
    chunk :: arena.current or_return false
    offset :: cast[usize](block) - arena_chunk_start(chunk)
    if size > chunk.capacity - offset {
        return false
    }
    if size > old_size {
        intrinsics.mem_zero(cast[mut rawptr](cast[usize](block) + old_size), size - old_size)
    }
    chunk.used = offset + size
    return true
}

/**
 * Find the start of a chunk's bytes, after its header.
 *
 * @param chunk A chunk of an arena, at the start of its header; only its address is used.
 * @return The address of its first byte for blocks, ARENA_CHUNK_HEADER bytes past the chunk.
 */
arena_chunk_start :: fn(chunk: ptr[ArenaChunk]) -> usize {
    return cast[usize](chunk) + ARENA_CHUNK_HEADER
}

/**
 * Take a block from the newest chunk, or from a new one when it doesn't fit.
 *
 * A new chunk is chunk_size bytes, or bigger when the block needs it, and becomes the newest; what was left in the one
 * before stays unused until a reset or restore.
 *
 * @param arena An arena from make_arena, not yet freed; a new chunk, when one is taken, becomes its
 *     newest.
 * @param size The block's size in bytes.
 * @param alignment The block's alignment in bytes: a power of two; 0 is taken as 1.
 * @return The block, zeroed; or null if backing has no memory for a new chunk, or size is too big to fit any.
 */
arena_take :: fn(arena: ptr[mut Arena], size: usize, alignment: usize) -> rawptr {
    align :: if alignment > 1 { alignment } else { cast[usize](1) }
    fitted :: arena_take_from_newest(arena, size, align)
    if fitted != null {
        return fitted
    }
    // A new chunk, big enough for the block aligned anywhere in it
    if size > ~cast[usize](0) - ARENA_CHUNK_HEADER - align {
        return null
    }
    needed :: ARENA_CHUNK_HEADER + size + align
    total :: if needed > arena.chunk_size { needed } else { arena.chunk_size }
    memory, error :: arena.backing.function(arena.backing.data, total, 16, null, 0)
    if error != null {
        return null
    }
    chunk :: cast[ptr[mut ArenaChunk]](memory.data)
    chunk^ = ArenaChunk.{previous = arena.current, capacity = total - ARENA_CHUNK_HEADER}
    arena.current = chunk
    start :: arena_chunk_start(chunk)
    at :: (start + align - 1) & ~(align - 1)
    chunk.used = (at - start) + size
    intrinsics.mem_zero(cast[mut rawptr](at), size)
    return cast[rawptr](at)
}

/**
 * Allocate, free or resize a block of an arena: the function of the allocator arena_allocator makes.
 *
 * @param allocator_data The arena, as a ptr[mut Arena].
 * @param size The block's new size in bytes; 0 frees old_memory.
 * @param alignment The block's alignment in bytes, which must be a power of two, or 0, which is taken as 1.
 * @param old_memory The block to free or resize, or null to allocate a new one.
 * @param old_size old_memory's size in bytes, as it was allocated.
 * @param location Where the allocation was asked for; an arena doesn't use it.
 * @return The block: size zeroed bytes, the old block's bytes copied to the start of it when resizing, which moves it
 *     unless it's the newest block and its chunk has room. Empty when freeing or failing. A block that's freed or
 *     moved away from is given back only if it's the newest; anything older waits for a reset, restore or free_arena.
 * @return null on success; OutOfMemory if backing has no memory for a chunk the block needs, the old block left as it
 *     was; InvalidArgument if alignment isn't a power of two.
 */
arena_function : runtime.AllocatorFn : fn(
    allocator_data: rawptr,
    size: usize,
    alignment: usize,
    old_memory: rawptr,
    old_size: usize,
    location := #caller_location,
) -> (mut u8[], runtime.AllocatorError?) {
    arena :: cast[ptr[mut Arena]](allocator_data)
    empty : mut u8[]
    if alignment & (alignment - 1) != 0 {
        return empty, runtime.AllocatorError.InvalidArgument
    }
    newest :: old_memory != null && cast[usize](old_memory) == arena.last
    if size == 0 {
        // Only the newest block comes back; anything older waits for a reset
        if newest {
            arena_give_back_newest(arena, old_memory)
        }
        return empty, null
    }
    // The newest block grows or shrinks where it is, if its chunk has room
    if newest && arena_resize_newest(arena, old_memory, old_size, size) {
        return view_of(cast[ptr[mut u8]](old_memory), size), null
    }
    block :: arena_take(arena, size, alignment)
    if block == null {
        return empty, runtime.AllocatorError.OutOfMemory
    }
    if old_memory != null {
        intrinsics.mem_copy(cast[mut rawptr](block), old_memory, if old_size < size { old_size } else { size })
    }
    arena.last = cast[usize](block)
    return view_of(cast[ptr[mut u8]](block), size), null
}

package memory

import intrinsics from "base"
import runtime from "base"

/**
 * An arena: a bump allocator over chunks it takes from another allocator, for memory that's all given back at once,
 * like what a frame or a request builds and drops. Allocating moves a chunk's offset on; freeing gives back only the
 * newest block, so temporaries made and freed in turn unwind, and anything else stays until the arena is reset, restored
 * to a mark, or freed. Blocks are zeroed, as other allocators' are.
 *
 *     frame :: memory.make_arena() or_return 1
 *     defer memory.free_arena(frame)
 *     info := memory.new_value(Info.{count = 3}, memory.arena_allocator(frame))
 *     // ...
 *     memory.reset_arena(frame)       // everything from it is gone; its first chunk is kept for next time
 *
 * Memory from an arena is like any allocator's: pointers to it can be kept in structs, dynamic arrays and the heap,
 * unlike pointers into the stack (docs/memory.md, Pointers to the Stack), and they're valid until the arena gives it
 * back. An arena isn't for sharing: one thread uses it at a time.
 */
Arena :: struct {
    backing : runtime.Allocator,
    /** The size of each chunk taken from backing, header included; a larger block gets a chunk of its own size */
    chunk_size : usize,
    /** The newest chunk, which blocks come from, holding the one before it */
    current : ptr[mut ArenaChunk]?,
    /** The newest block's address, which freeing gives back and resizing grows in place, or 0 */
    last : usize,
}

/** A chunk of an arena: this header, then the bytes blocks are taken from. */
ArenaChunk :: struct {
    previous : ptr[mut ArenaChunk]?,
    /** Bytes after the header */
    capacity : usize,
    /** Bytes after the header given out so far */
    used : usize,
}

/** Where an arena was, for arena_restore to go back to. */
ArenaMark :: struct {
    chunk : ptr[mut ArenaChunk]?,
    used : usize,
}

/**
 * The header before each chunk's bytes, kept a multiple of 16 so blocks of up to 16-byte alignment pack from the start.
 */
ARENA_CHUNK_HEADER :: (size_of(ArenaChunk) + 15) & ~cast[usize](15)

ARENA_DEFAULT_CHUNK_SIZE : usize : 64 * 1024

/**
 * An arena taking chunks of chunk_size bytes from backing, made with backing, since the allocator it is holds it
 * (arena_allocator): null if there's no memory for it. It takes no chunk until something is allocated. free_arena gives
 * it back.
 */
make_arena :: fn(chunk_size := ARENA_DEFAULT_CHUNK_SIZE, backing := context.allocator) -> ptr[mut Arena]? {
    made, error :: runtime.new_aligned(Arena, align_of(Arena), backing)
    if error != null {
        return null
    }
    made^ = Arena.{backing = backing, chunk_size = if chunk_size > ARENA_CHUNK_HEADER { chunk_size } else { ARENA_DEFAULT_CHUNK_SIZE }}
    return made
}

/** Gives back every chunk and the arena itself. */
free_arena :: fn(arena: ptr[mut Arena]) {
    arena_free_chunks(arena, null)
    runtime.free_aligned(arena, align_of(Arena), arena.backing)
}

/** The allocator an Arena is, which it must outlive. */
arena_allocator :: fn(arena #escaping : ptr[mut Arena]) -> runtime.Allocator {
    return runtime.Allocator.{arena_function, cast[rawptr](arena)}
}

/**
 * Gives back everything allocated from the arena, keeping its first chunk to allocate from again and giving the others
 * back to the backing allocator.
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

/** Where the arena is now, to give back what's allocated after it with arena_restore. */
arena_mark :: fn(arena: ptr[Arena]) -> ArenaMark {
    chunk :: arena.current or_return ArenaMark.{}
    return ArenaMark.{chunk = chunk, used = chunk.used}
}

/**
 * Gives back everything allocated since mark was taken, with the chunks taken since. A mark taken before the arena had
 * a chunk gives back every chunk. Where the arena already gave back what the mark covers, by a reset or by restoring an
 * earlier mark, there's nothing more to give back, and it's left as it is.
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

/** Whether the arena is past mark: mark's chunk is still one of its chunks, with no less of it used than then. */
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

/** How many bytes the arena has given out and not given back, across its chunks. */
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
 * A new T from allocator, holding value, like a literal with some of its fields given: runtime.new, then the value
 * stored. If it can't be allocated, calls context.assertion_handler, as new does.
 */
new_value :: fn[T](value #escaping : T, allocator := context.allocator, loc := #caller_location) -> ptr[mut T] {
    made :: runtime.new(T, allocator, loc)
    made^ = value
    return made
}

/** Gives back the chunks newer than keep, all of them when keep is null, leaving keep the newest. */
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

/** size zeroed bytes aligned to align from the newest chunk, or null if it has no room. */
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

/** Gives back the newest block, block. */
arena_give_back_newest :: fn(arena: ptr[mut Arena], block: rawptr) {
    arena.last = 0
    chunk :: arena.current or_return void
    chunk.used = cast[usize](block) - arena_chunk_start(chunk)
}

/** Resizes the newest block, block, where it is: false if its chunk has no room. */
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

/** The start of a chunk's bytes. */
arena_chunk_start :: fn(chunk: ptr[ArenaChunk]) -> usize {
    return cast[usize](chunk) + ARENA_CHUNK_HEADER
}

/**
 * size zeroed bytes aligned to alignment from the newest chunk, or a new one when they don't fit: null if backing has no
 * memory for it.
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

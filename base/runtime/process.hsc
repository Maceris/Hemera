package runtime

/*
 * What the runtime keeps for the whole process, in the one global the program has for it
 * (intrinsics.process_state), zeroed when the program starts.
 */
ProcessState :: struct {
    /*
     * One more than the thread-local storage slot that holds each thread's carrier block, for
     * callbacks from foreign code to find it, or 0 until it's allocated (register_carrier, Windows).
     */
    carrier_slot : u32,
    // The heap on systems where the runtime makes its own from pages (linux.hsc)
    heap : PageHeap,
}

// Size classes of PageHeap's small blocks: 16 bytes, doubling, to 2 KiB.
PAGE_HEAP_CLASSES :: 8
// What each class's blocks are carved from.
PAGE_HEAP_CHUNK :: 65536

/*
 * A heap made from pages the system maps: blocks of up to 2 KiB come from one free list per size
 * class, carved from 64 KiB chunks, and bigger ones are pages of their own. Every block has 16
 * bytes in front of it: its class, or for a block of its own pages, how many bytes of pages there
 * are, then where they start. One lock guards it all, held for a few instructions (or a chunk's
 * mapping). Chunks are kept for the rest of the process.
 */
PageHeap :: struct {
    // 0 when free, 1 when held
    lock : u32,
    // Free blocks of each class, linked through their first word
    free_lists : rawptr[PAGE_HEAP_CLASSES],
}

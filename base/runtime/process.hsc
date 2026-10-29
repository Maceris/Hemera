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
    /*
     * On Linux, what the entry was given, as C's main is: argc, argv, and envp (each a pointer to
     * null-terminated pointers to null-terminated strings). Zero elsewhere.
     */
    argument_count : usize,
    argument_pointers : rawptr,
    environment_pointers : rawptr,
    // On SlopOS, the startup block the entry was given, and how much of its free range the heap has mapped
    startup_block : rawptr,
    mapped : u64,
    /*
     * On SlopOS, the random generator seeded from the startup block (slop_os.hsc): its key, the bytes of its last
     * block not given out yet from random_used, whether it's seeded, and its lock
     */
    random_key : u8[32],
    random_output : u8[32],
    random_used : u32,
    random_seeded : u32,
    random_lock : u32,
    // process_arguments: 0 until someone starts on them, 1 while they're worked out, 2 once they're there
    arguments_state : u32,
    arguments : string[],
    // On SlopOS, the clock page the wall clock is read from (slop_os.hsc), once it's mapped, and how far that's got
    clock_page : rawptr,
    clock_state : u32,
    // On SlopOS, what the logger keeps for the events service (slop_os_events.hsc), once its ring is mapped, and how
    // far that's got, as clock_state
    events_log : rawptr,
    events_state : u32,
}

// ProcessState's clock_state and events_state: not looked for yet, being mapped, mapped, or there's none.
CLOCK_PAGE_UNTRIED : u32 : 0
CLOCK_PAGE_MAPPING : u32 : 1
CLOCK_PAGE_MAPPED : u32 : 2
CLOCK_PAGE_NONE : u32 : 3

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

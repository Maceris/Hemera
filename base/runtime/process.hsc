package runtime

/**
 * What the runtime keeps for the whole process, in the one global the program has for it
 * (intrinsics.process_state), zeroed when the program starts.
 */
ProcessState :: struct {
    /**
     * One more than the thread-local storage slot that holds each thread's carrier block, for
     * callbacks from foreign code to find it, or 0 until it's allocated (register_carrier, Windows).
     */
    carrier_slot : u32,
    /** The heap on systems where the runtime makes its own from pages (page_heap.hsc); unused elsewhere. */
    heap : PageHeap,
    /** On Linux, argc, as C's main gets it: how many pointers argument_pointers has before its null. 0 elsewhere. */
    argument_count : usize,
    /**
     * On Linux, argv, as C's main is given it: a pointer to null-terminated pointers to the program's arguments, each a
     * null-terminated string, the system's for the whole process. Null elsewhere.
     */
    argument_pointers : rawptr,
    /**
     * On Linux, envp, as C's main is given it: a pointer to null-terminated pointers to the environment's
     * null-terminated NAME=value strings. Null elsewhere.
     */
    environment_pointers : rawptr,
    /** On UEFI, the image's handle the entry was given (uefi.hsc). Null elsewhere. */
    uefi_image : rawptr,
    /** On UEFI, the system table the entry was given (uefi.hsc). Null elsewhere. */
    uefi_system_table : rawptr,
    /** On SlopOS, the startup block the entry was given. Null elsewhere, or when there was none. */
    startup_block : rawptr,
    /**
     * On SlopOS, whether the process runs in the deterministic mode (deterministic_turn): 0 before it's looked up,
     * 1 off, 2 on. Written atomically; 0 elsewhere, where the mode isn't.
     */
    deterministic : u32,
    /**
     * On SlopOS, how many bytes of the startup block's free range of addresses have been handed out, for the heap and
     * other mappings; only grows, atomically.
     */
    mapped : u64,
    /** On SlopOS, the key of the random generator seeded from the startup block (slop_os.hsc). */
    random_key : u8[32],
    /** On SlopOS, the random generator's last block of output, given out a byte at a time. */
    random_output : u8[32],
    /** On SlopOS, how many of random_output's bytes have been given out, 0 to 32; 32 makes a new block next. */
    random_used : u32,
    /** On SlopOS, 1 once the random generator is seeded, 0 before. */
    random_seeded : u32,
    /** On SlopOS, the random generator's spin lock: 0 when free, 1 when held. */
    random_lock : u32,
    /** For process_arguments: 0 until someone starts on them, 1 while they're worked out, 2 once they're there. */
    arguments_state : u32,
    /** The process's arguments, once arguments_state is 2; kept for the rest of the process. */
    arguments : string[],
    /** On SlopOS, the clock page the wall clock is read from (slop_os.hsc), once it's mapped; null before. */
    clock_page : rawptr,
    /** On SlopOS, how far mapping clock_page has got: one of the CLOCK_PAGE_ constants. */
    clock_state : u32,
    /**
     * On SlopOS, what the logger keeps for the events service (slop_os_events.hsc), once its ring is mapped; null
     * before.
     */
    events_log : rawptr,
    /** On SlopOS, how far mapping events_log has got: one of the CLOCK_PAGE_ constants, as clock_state. */
    events_state : u32,
    /** On SlopOS, 1 once the lifecycle channel asked the program to stop (slop_os_lifecycle.hsc), 0 before. */
    stop_requested : u32,
    /** On SlopOS, the port to wake when the program is asked to stop, or 0 for none (slop_os_lifecycle.hsc). */
    stop_port : u64,
    /** On SlopOS, the key the wake on stop_port carries, which slop_os_on_stop was given. */
    stop_key : u64,
    /** On SlopOS, the name of the locale the process was given (its grant "locale"), once it's read. */
    locale_name : u8[LOCALE_NAME_BYTES],
    /** On SlopOS, how many of locale_name's bytes hold the name, at most LOCALE_NAME_BYTES. */
    locale_name_count : usize,
    /** On SlopOS, how far reading locale_name has got: one of the CLOCK_PAGE_ constants, as clock_state. */
    locale_state : u32,
    /**
     * On SlopOS, the grant "arguments" the entry's value parameters are read from (slop_os.hsc, os_entry_value),
     * once it's mapped, by the entry, before main; null before, or when there's none.
     */
    entry_arguments : rawptr,
    /** On SlopOS, how many bytes entry_arguments holds. */
    entry_arguments_bytes : u64,
    /** On SlopOS, whether mapping entry_arguments has been tried, so it's tried only once. */
    entry_arguments_tried : bool,
}

/** The most bytes of a locale's name the process keeps, as "en-GB" is 5. */
LOCALE_NAME_BYTES :: 32

/**
 * Fetch the name of the locale the process was given.
 *
 * On SlopOS it's what the process's grant "locale" holds, which whoever launched it gave it (std/os's
 * LaunchOptions.locale); elsewhere there's none. Only std/locale reads it, for human-facing text: nothing else in base
 * changes with it.
 *
 * @return The name, like "en-GB", at most LOCALE_NAME_BYTES bytes, kept by the process for the rest of its life; or ""
 *     for none.
 */
locale_name :: fn() -> string {
    #if OS == .SlopOS && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {
        return slop_os_locale_name()
    }
    #else {
        return ""
    }
}

// ProcessState's clock_state, events_state and locale_state: not looked for yet, being mapped, mapped, or there's none.
/** Not looked for yet: the first to claim it, moving it to CLOCK_PAGE_MAPPING, maps it. */
CLOCK_PAGE_UNTRIED : u32 : 0
/** Being mapped by whoever claimed it; others wanting it spin until it's MAPPED or NONE. */
CLOCK_PAGE_MAPPING : u32 : 1
/** Mapped, and there to read for the rest of the process. */
CLOCK_PAGE_MAPPED : u32 : 2
/** There's none, or mapping it failed; it isn't tried again. */
CLOCK_PAGE_NONE : u32 : 3

/** The number of size classes of PageHeap's small blocks: 16 bytes, doubling, to 2 KiB. */
PAGE_HEAP_CLASSES :: 8
/** The size in bytes of the chunks each class's blocks are carved from, mapped one at a time as a class runs out. */
PAGE_HEAP_CHUNK :: 65536

/**
 * A heap made from pages the system maps: blocks of up to 2 KiB come from one free list per size
 * class, carved from 64 KiB chunks, and bigger ones are pages of their own. Every block has 16
 * bytes in front of it: its class, or for a block of its own pages, how many bytes of pages there
 * are, then where they start. One lock guards it all, held for a few instructions (or a chunk's
 * mapping). Chunks are kept for the rest of the process.
 */
PageHeap :: struct {
    /** The spin lock guarding the free lists: 0 when free, 1 when held. */
    lock : u32,
    /** The free blocks of each class, by their headers, linked through their first word; null when a class has none. */
    free_lists : rawptr[PAGE_HEAP_CLASSES],
}

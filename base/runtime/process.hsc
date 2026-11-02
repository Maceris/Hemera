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
    // On UEFI, the image's handle and the system table the entry was given (uefi.hsc)
    uefi_image : rawptr,
    uefi_system_table : rawptr,
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
    // On SlopOS, whether the lifecycle channel asked the program to stop, and the port and key to wake when it does
    // (slop_os_lifecycle.hsc)
    stop_requested : u32,
    stop_port : u64,
    stop_key : u64,
    // On SlopOS, the name of the locale the process was given (its grant "locale"), once it's read, and how far that's
    // got, as clock_state
    locale_name : u8[LOCALE_NAME_BYTES],
    locale_name_count : usize,
    locale_state : u32,
}

// The most bytes of a locale's name the process keeps, as "en-GB" is 5.
LOCALE_NAME_BYTES :: 32

/*
 * The name of the locale the process was given, or "" for none: on SlopOS, what its grant "locale" holds, which whoever
 * launched it gave it (std/os's LaunchOptions.locale); elsewhere none. Only std/locale reads it, for human-facing text:
 * nothing else in base changes with it.
 */
locale_name :: fn() -> string {
    #if OS == .SlopOS && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {
        return slop_os_locale_name()
    }
    #else {
        return ""
    }
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

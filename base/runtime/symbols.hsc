package runtime

import intrinsics from "base"

/*
 * Naming the frames of a stack trace while the program runs. A program built with debug info
 * (--debug) has a table of its Hemera functions' starts and names (intrinsics.function_names), so a
 * return address can be named as the function it's in and how far into it:
 *
 *     name, offset :: runtime.function_at(address)   // "loader.load_file", 0x4c
 *
 * Inlined functions are part of the function they were inlined into, and code that isn't Hemera's,
 * like the system's, has no name. `hemera --symbolize` gives files and lines, inlined calls
 * included, from the program's debug info (docs/compilation.md, Debug Info).
 */

/** One entry of the program's table of functions (intrinsics.function_names), which a build with --debug has. */
FunctionName :: struct {
    /** The address of the function's first instruction, as loaded. */
    start : rawptr,
    /**
     * The function's name, like "loader.load_file"; empty for code that isn't a Hemera function, like the program's
     * entry, which marks where the one before it ends.
     */
    name : string,
}

/**
 * How many bytes past a function's start an address can be and still be named as in it: 1 MiB, so an address far
 * past the last function in the table isn't named as in it.
 */
FUNCTION_NAME_REACH : usize : 0x100000

/**
 * Name the function an instruction address is in, and how far into it.
 *
 * For a return address, which may be just past a call at the end of a function, ask about the address before it.
 *
 * @param address The instruction's address, as loaded.
 * @return name The name of the function in the table that starts closest at or before address, in the program's
 *     image for its whole life; "" when there's none, when that entry is unnamed, when address is FUNCTION_NAME_REACH
 *     or more past its start, or when the program has no table.
 * @return offset How many bytes past the function's start address is; 0 whenever name is "".
 */
function_at #no_context :: fn(address: rawptr) -> (name: string, offset: usize) {
    best_name := ""
    best_start : usize = 0
    found := false
    target :: cast[usize](address)
    for entry in intrinsics.function_names() {
        start :: cast[usize](entry.start)
        if start <= target && (!found || start > best_start) {
            best_name = entry.name
            best_start = start
            found = true
        }
    }
    if !found || best_name.count == 0 || target - best_start >= FUNCTION_NAME_REACH {
        return "", 0
    }
    return best_name, target - best_start
}

/**
 * Turn an address into its offset in the program's image (intrinsics.image_base), as tools reading the program's file
 * want it.
 *
 * @param address Any address.
 * @return How many bytes past the image's start address is; or the address itself, unchanged, when the image's start
 *     isn't known or address is below it.
 */
image_offset #no_context :: fn(address: rawptr) -> usize {
    base :: cast[usize](intrinsics.image_base())
    if base == 0 || cast[usize](address) < base {
        return cast[usize](address)
    }
    return cast[usize](address) - base
}

/**
 * Tell whether an address is in the program's image (intrinsics.image_base).
 *
 * The image's span comes from its own headers: the span of an ELF image's loaded segments, or a PE/COFF image's
 * SizeOfImage. A string literal is in it; what's on the heap or the stack isn't.
 *
 * @param address Any address.
 * @return True when address is within the image's span; false when it isn't, and wherever the image's start isn't
 *     known or its headers can't be read, like an ELF image whose headers aren't in memory.
 */
in_image #no_context :: fn(address: rawptr) -> bool {
    base :: cast[usize](intrinsics.image_base())
    target :: cast[usize](address)
    if base == 0 || target < base {
        return false
    }
    return target - base < image_size(base)
}

/**
 * Measure how many bytes the image starting at base spans, from its headers.
 *
 * @param base The image's first byte, where its ELF or PE/COFF headers are; it has to be readable memory.
 * @return For ELF, the distance from the lowest address of its loaded segments to the highest they reach; for
 *     PE/COFF, its SizeOfImage. 0 if its headers aren't ones this reads, or an ELF image has no loaded segments.
 */
image_size #no_context :: fn(base: usize) -> usize {
    header :: cast[ptr[u8]](base)
    if read_at[u32](base, 0) == 0x464c457f {
        // ELF: the loaded segments, from the lowest address any has to the highest it reaches
        program_headers :: base + cast[usize](read_at[u64](base, 0x20))
        entry_size :: cast[usize](read_at[u16](base, 0x36))
        count :: cast[usize](read_at[u16](base, 0x38))
        lowest := ~cast[u64](0)
        highest : u64 = 0
        for i in cast[usize](0)..<count {
            at :: program_headers + i * entry_size
            // PT_LOAD
            if read_at[u32](at, 0) != 1 {
                continue
            }
            start :: read_at[u64](at, 0x10)
            end :: start + read_at[u64](at, 0x28)
            lowest = if start < lowest { start } else { lowest }
            highest = if end > highest { end } else { highest }
        }
        return if highest > lowest { cast[usize](highest - lowest) } else { 0 }
    }
    if header^ == 0x4d && read_at[u8](base, 1) == 0x5a {
        // PE/COFF: SizeOfImage, in the optional header after the "PE\0\0" signature and the file header
        signature :: base + cast[usize](read_at[u32](base, 0x3c))
        if read_at[u32](signature, 0) != 0x00004550 {
            return 0
        }
        return cast[usize](read_at[u32](signature, 24 + 56))
    }
    return 0
}

/**
 * Read a value from memory at an address and offset, for parsing headers.
 *
 * @tparam T The type read, like u32; read as the machine's byte order, little-endian on the targets this parses for.
 * @param base The address, as a number.
 * @param offset How many bytes past base the value is.
 * @return The value there. The memory has to be readable; nothing is checked.
 */
read_at #no_context :: fn[T](base: usize, offset: usize) -> T {
    return cast[ptr[T]](base + offset)^
}

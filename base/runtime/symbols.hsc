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
FunctionName :: struct {
    start : rawptr,
    // Empty for code that isn't a Hemera function, like the program's entry, which marks where the one before it ends
    name : string,
}

// How far past a function's start an address can be and still be named as in it.
FUNCTION_NAME_REACH : usize : 0x100000

/*
 * The function an instruction address is in, and how far into it, or "" if it's in none the table
 * has. For a return address, which may be just past a call at the end of a function, ask about
 * the address before it.
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

// address relative to the program's image (intrinsics.image_base), or the address itself if that isn't known.
image_offset #no_context :: fn(address: rawptr) -> usize {
    base :: cast[usize](intrinsics.image_base())
    if base == 0 || cast[usize](address) < base {
        return cast[usize](address)
    }
    return cast[usize](address) - base
}

/*
 * Whether an address is in the program's image (intrinsics.image_base), from the image's own headers: the span of an
 * ELF image's loaded segments, or a PE/COFF image's SizeOfImage. A string literal is; what's on the heap or the stack
 * isn't. False wherever the image's start isn't known, like an ELF image whose headers aren't in memory.
 */
in_image #no_context :: fn(address: rawptr) -> bool {
    base :: cast[usize](intrinsics.image_base())
    target :: cast[usize](address)
    if base == 0 || target < base {
        return false
    }
    return target - base < image_size(base)
}

// How many bytes the image starting at base spans, or 0 if its headers aren't ones this reads.
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

read_at #no_context :: fn[T](base: usize, offset: usize) -> T {
    return cast[ptr[T]](base + offset)^
}

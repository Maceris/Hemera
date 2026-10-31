package runtime

import intrinsics from "base"

/*
 * Loading a typed library on SlopOS (libraries.hsc; the SlopOS repository's decisions 0119, 0120): whoever launched the
 * program gave it each library it imports as a grant, library:<the library's file>, read-only memory holding the file,
 * from the bundle store or a boot module. Its segments that aren't written are mapped from that memory, so every process
 * using the library shares their pages, its text read and execute; each that is written is copied into memory of the
 * program's own. Its relative relocations are applied, only ever within those copies, and its interface record is
 * found at its entry, where the compiler puts it. Anything else, a relocation of another kind or one into what's
 * shared, refuses the library.
 */
#if OS == .SlopOS {
    SLOP_OS_CALL_MEMORY_SIZE : u64 : 49
    SLOP_OS_PROTECTION_READ_EXECUTE : u64 : 5
    LIBRARY_GRANT_PREFIX :: "library:"
    LIBRARY_PAGE : u64 : 4096
    LIBRARY_PT_LOAD : u32 : 1
    LIBRARY_PT_DYNAMIC : u32 : 2
    LIBRARY_PF_WRITE : u32 : 2
    LIBRARY_PF_EXECUTE : u32 : 1
    LIBRARY_DT_NULL : u64 : 0
    LIBRARY_DT_RELA : u64 : 7
    LIBRARY_DT_RELASZ : u64 : 8
    LIBRARY_DT_RELAENT : u64 : 9
    LIBRARY_DT_REL : u64 : 17
    LIBRARY_DT_JMPREL : u64 : 23
    LIBRARY_DT_RELR : u64 : 36
    // The most loadable segments a library has
    LIBRARY_MAX_SEGMENTS :: 8

    #if TARGET_ARCH == .x86_64 {
        LIBRARY_ELF_MACHINE : u16 : 62
        LIBRARY_RELATIVE_RELOCATION : u32 : 8
    }
    #else {
        LIBRARY_ELF_MACHINE : u16 : 183
        LIBRARY_RELATIVE_RELOCATION : u32 : 1027
    }

    LibraryElfHeader :: struct {
        ident : u8[16],
        type : u16,
        machine : u16,
        version : u32,
        entry : u64,
        program_headers : u64,
        section_headers : u64,
        flags : u32,
        header_size : u16,
        program_header_size : u16,
        program_header_count : u16,
        section_header_size : u16,
        section_header_count : u16,
        section_names : u16,
    }

    LibraryProgramHeader :: struct {
        type : u32,
        flags : u32,
        offset : u64,
        address : u64,
        physical : u64,
        file_size : u64,
        memory_size : u64,
        alignment : u64,
    }

    LibraryRela :: struct {
        offset : u64,
        info : u64,
        addend : i64,
    }

    // A written segment's pages, copied for this program: where they are, from the library's base
    LibraryCopy :: struct {
        start : u64,
        end : u64,
    }

    // The library given as the grant library:<name>, loaded: its interface record, or null.
    os_load_library :: fn(name: string) -> ptr[LibraryInterface]? {
        state :: intrinsics.process_state()
        if state.startup_block == null {
            return null
        }
        startup :: cast[ptr[SlopOsStartup]](state.startup_block)
        label_storage : u8[32]
        label_count := cast[usize](0)
        for text in string.[LIBRARY_GRANT_PREFIX, name] {
            for byte in string_bytes(text) {
                if label_count >= label_storage.count {
                    return null
                }
                label_storage[label_count] = byte
                label_count += 1
            }
        }
        handle :: cast[u64](os_entry_grant(string_of(&label_storage[0], label_count), "Memory", "", false))
        if handle == 0 {
            return null
        }
        sized :: slop_os_call(SLOP_OS_CALL_MEMORY_SIZE, handle)
        if sized.tag != 0 || sized.first < cast[u64](size_of(LibraryElfHeader)) {
            return null
        }
        file_size :: sized.first
        // The whole file, read-only, to read its headers and copy its written segments from
        file :: reserve_addresses(cast[usize](file_size)) or_return null
        if slop_os_call(SLOP_OS_CALL_MEMORY_MAP, handle, cast[u64](startup.space), file, 0, file_size, SLOP_OS_PROTECTION_READ).tag != 0 {
            return null
        }
        defer slop_os_call(SLOP_OS_CALL_MEMORY_UNMAP, cast[u64](startup.space), file)
        elf :: cast[ptr[LibraryElfHeader]](cast[uintptr](file))
        if elf.ident[0] != 0x7f || elf.ident[1] != 0x45 || elf.ident[2] != 0x4c || elf.ident[3] != 0x46 || elf.ident[4] != 2
            || elf.ident[5] != 1 || elf.type != 3 || elf.machine != LIBRARY_ELF_MACHINE
            || cast[usize](elf.program_header_size) != size_of(LibraryProgramHeader) {
            return null
        }
        count :: cast[u64](elf.program_header_count)
        if elf.program_headers > file_size || count * cast[u64](size_of(LibraryProgramHeader)) > file_size - elf.program_headers {
            return null
        }
        program :: view_of(cast[ptr[LibraryProgramHeader]](cast[uintptr](file + elf.program_headers)), cast[usize](count))
        lowest := ~cast[u64](0)
        highest : u64 = 0
        for each in program {
            if each.type == LIBRARY_PT_LOAD {
                if each.offset > file_size || each.file_size > file_size - each.offset || each.file_size > each.memory_size
                    || (each.offset & (LIBRARY_PAGE - 1)) != (each.address & (LIBRARY_PAGE - 1)) {
                    return null
                }
                start :: each.address & ~(LIBRARY_PAGE - 1)
                end :: (each.address + each.memory_size + LIBRARY_PAGE - 1) & ~(LIBRARY_PAGE - 1)
                lowest = if start < lowest { start } else { lowest }
                highest = if end > highest { end } else { highest }
            }
        }
        if highest <= lowest {
            return null
        }
        reserved :: reserve_addresses(cast[usize](highest - lowest)) or_return null
        base :: reserved - lowest
        copies : LibraryCopy[LIBRARY_MAX_SEGMENTS]
        copy_count := cast[usize](0)
        for each in program {
            if each.type != LIBRARY_PT_LOAD {
                continue
            }
            start :: each.address & ~(LIBRARY_PAGE - 1)
            end :: (each.address + each.memory_size + LIBRARY_PAGE - 1) & ~(LIBRARY_PAGE - 1)
            if each.flags & LIBRARY_PF_WRITE == 0 {
                // Shared: mapped from the library's memory, the pages it's in, which must all be the file's
                from :: each.offset & ~(LIBRARY_PAGE - 1)
                if end - start > file_size - from {
                    return null
                }
                protection :: if each.flags & LIBRARY_PF_EXECUTE != 0 { SLOP_OS_PROTECTION_READ_EXECUTE } else { SLOP_OS_PROTECTION_READ }
                if slop_os_call(SLOP_OS_CALL_MEMORY_MAP, handle, cast[u64](startup.space), base + start, from, end - start, protection).tag != 0 {
                    return null
                }
                continue
            }
            // The program's own: zeroed, then filled from the file
            if copy_count >= copies.count {
                return null
            }
            created :: slop_os_call(SLOP_OS_CALL_MEMORY_CREATE, cast[u64](startup.budget), end - start)
            if created.tag != 0 {
                return null
            }
            if slop_os_call(SLOP_OS_CALL_MEMORY_MAP, created.first, cast[u64](startup.space), base + start, 0, end - start,
                SLOP_OS_PROTECTION_READ_WRITE).tag != 0 {
                return null
            }
            intrinsics.mem_copy_non_overlapping(cast[mut rawptr](cast[uintptr](base + each.address)), cast[rawptr](cast[uintptr](file + each.offset)),
                cast[usize](each.file_size))
            copies[copy_count] = LibraryCopy.{start = start, end = end}
            copy_count += 1
        }
        made :: if copy_count <= copies.count { copies[0..<copy_count] } else { copies[0..<0] }
        for each in program {
            if each.type == LIBRARY_PT_DYNAMIC && !relocate_library(base, each.address, made) {
                return null
            }
        }
        return cast[ptr[LibraryInterface]](cast[uintptr](base + elf.entry))
    }

    // The library's dynamic section at address applied: its relative relocations, each within a copy, and nothing else.
    relocate_library :: fn(base: u64, address: u64, copies: LibraryCopy[]) -> bool {
        if !within_copies(address, 16, copies) {
            return false
        }
        relocations : u64 = 0
        bytes : u64 = 0
        entry_size := cast[u64](size_of(LibraryRela))
        at := base + address
        loop {
            tag :: cast[ptr[u64]](cast[uintptr](at))^
            value :: cast[ptr[u64]](cast[uintptr](at + 8))^
            if tag == LIBRARY_DT_NULL {
                break
            }
            if tag == LIBRARY_DT_RELA {
                relocations = value
            }
            else if tag == LIBRARY_DT_RELASZ {
                bytes = value
            }
            else if tag == LIBRARY_DT_RELAENT {
                entry_size = value
            }
            else if tag == LIBRARY_DT_REL || tag == LIBRARY_DT_JMPREL || tag == LIBRARY_DT_RELR {
                return false
            }
            at += 16
            if !within_copies(at - base, 16, copies) {
                return false
            }
        }
        if relocations == 0 || bytes == 0 {
            return true
        }
        if entry_size != cast[u64](size_of(LibraryRela)) {
            return false
        }
        for i in cast[u64](0)..<bytes / entry_size {
            each :: cast[ptr[LibraryRela]](cast[uintptr](base + relocations + i * entry_size))
            if cast[u32](each.info & 0xffffffff) != LIBRARY_RELATIVE_RELOCATION || !within_copies(each.offset, 8, copies) {
                return false
            }
            cast[ptr[mut u64]](cast[uintptr](base + each.offset))^ = base + cast[u64](each.addend)
        }
        return true
    }

    // Whether bytes at offset, from the library's base, are all within one of its copies.
    within_copies :: fn(offset: u64, bytes: u64, copies: LibraryCopy[]) -> bool {
        for copy in copies {
            if offset >= copy.start && offset + bytes <= copy.end {
                return true
            }
        }
        return false
    }
}

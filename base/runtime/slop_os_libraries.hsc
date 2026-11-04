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
    /** The system call that gives a memory object's size in bytes, in its answer's first result. */
    SLOP_OS_CALL_MEMORY_SIZE : u64 : 49
    /** A mapping's protection: readable and executable, not writable, for a library's text. */
    SLOP_OS_PROTECTION_READ_EXECUTE : u64 : 5
    /** What a library's grant's label starts with, its file's name following. */
    LIBRARY_GRANT_PREFIX :: "library:"
    /** The size of a page, in bytes, which a library's segments are mapped and copied in. */
    LIBRARY_PAGE : u64 : 4096
    /** ELF's PT_LOAD: a program header for a segment to load. */
    LIBRARY_PT_LOAD : u32 : 1
    /** ELF's PT_DYNAMIC: a program header for the dynamic section, which says where the relocations are. */
    LIBRARY_PT_DYNAMIC : u32 : 2
    /** ELF's PF_W: a segment's flag that it's written, so it's copied rather than shared. */
    LIBRARY_PF_WRITE : u32 : 2
    /** ELF's PF_X: a segment's flag that it's executed, so it's mapped executable. */
    LIBRARY_PF_EXECUTE : u32 : 1
    /** ELF's DT_NULL: the dynamic section's last entry. */
    LIBRARY_DT_NULL : u64 : 0
    /** ELF's DT_RELA: where the Rela relocations are, from the library's base. */
    LIBRARY_DT_RELA : u64 : 7
    /** ELF's DT_RELASZ: the Rela relocations' size, in bytes. */
    LIBRARY_DT_RELASZ : u64 : 8
    /** ELF's DT_RELAENT: one Rela relocation's size, in bytes, which has to be a LibraryRela's. */
    LIBRARY_DT_RELAENT : u64 : 9
    /** ELF's DT_REL: Rel relocations, which refuse the library. */
    LIBRARY_DT_REL : u64 : 17
    /** ELF's DT_JMPREL: the procedure linkage table's relocations, which refuse the library. */
    LIBRARY_DT_JMPREL : u64 : 23
    /** ELF's DT_RELR: packed relative relocations, which refuse the library. */
    LIBRARY_DT_RELR : u64 : 36
    /** The most loadable segments a library has that are written, and so copied; one with more is refused. */
    LIBRARY_MAX_SEGMENTS :: 8

    #if TARGET_ARCH == .x86_64 {
        /** ELF's e_machine for x86-64, EM_X86_64; a library for another machine is refused. */
        LIBRARY_ELF_MACHINE : u16 : 62
        /** x86-64's relative relocation, R_X86_64_RELATIVE: base plus addend, stored at the offset. */
        LIBRARY_RELATIVE_RELOCATION : u32 : 8
    }
    #else {
        /** ELF's e_machine for AArch64, EM_AARCH64; a library for another machine is refused. */
        LIBRARY_ELF_MACHINE : u16 : 183
        /** AArch64's relative relocation, R_AARCH64_RELATIVE: base plus addend, stored at the offset. */
        LIBRARY_RELATIVE_RELOCATION : u32 : 1027
    }

    /** A 64-bit ELF file's header, at the start of a library's file. */
    LibraryElfHeader :: struct {
        /** The magic "\x7fELF", the class (2, 64-bit), the data encoding (1, little-endian), and the rest. */
        ident : u8[16],
        /** The file's type, which has to be 3, ET_DYN, a shared object. */
        type : u16,
        /** The machine it's for, which has to be LIBRARY_ELF_MACHINE. */
        machine : u16,
        /** ELF's version; not checked. */
        version : u32,
        /** The entry's address from the library's base, where the compiler puts its interface record. */
        entry : u64,
        /** Where the program headers are, in bytes from the file's start. */
        program_headers : u64,
        /** Where the section headers are, in bytes from the file's start; unused. */
        section_headers : u64,
        /** Machine-specific flags; unused. */
        flags : u32,
        /** This header's size, in bytes; unused. */
        header_size : u16,
        /** One program header's size, in bytes, which has to be a LibraryProgramHeader's. */
        program_header_size : u16,
        /** How many program headers there are. */
        program_header_count : u16,
        /** One section header's size, in bytes; unused. */
        section_header_size : u16,
        /** How many section headers there are; unused. */
        section_header_count : u16,
        /** The index of the section holding sections' names; unused. */
        section_names : u16,
    }

    /** A 64-bit ELF program header, describing one of a library's segments. */
    LibraryProgramHeader :: struct {
        /** What it describes: LIBRARY_PT_LOAD and LIBRARY_PT_DYNAMIC are read, and every other is ignored. */
        type : u32,
        /** The segment's LIBRARY_PF_ flags: whether it's written, and whether executed. */
        flags : u32,
        /** Where the segment's bytes are, in bytes from the file's start; within a page, the same as address. */
        offset : u64,
        /** Where the segment goes, from the library's base. */
        address : u64,
        /** Its physical address; unused. */
        physical : u64,
        /** How many of its bytes are in the file, at most memory_size. */
        file_size : u64,
        /** How many bytes it has in memory, the rest past file_size zeroed. */
        memory_size : u64,
        /** Its alignment; unused, as pages are what it's mapped in. */
        alignment : u64,
    }

    /** An ELF relocation with an addend (Elf64_Rela). */
    LibraryRela :: struct {
        /** Where it's applied, from the library's base, which has to be within a copy. */
        offset : u64,
        /** Its symbol and type; the low 32 bits, the type, have to be LIBRARY_RELATIVE_RELOCATION. */
        info : u64,
        /** What the library's base is added to, the value stored. */
        addend : i64,
    }

    /** A written segment's pages, copied for this program: where they are, from the library's base. */
    LibraryCopy :: struct {
        /** The first byte, page-aligned. */
        start : u64,
        /** The byte after the last, page-aligned. */
        end : u64,
    }

    /**
     * Load the library given as the grant library:<name>.
     *
     * Its segments that aren't written are mapped from the grant's memory, shared, and each that is written is copied
     * into memory of the program's own, made from its budget; its relative relocations are then applied. The file's
     * own mapping is unmapped before it returns. A library that fails partway leaves what was mapped and made so far
     * where it is, and the addresses it took from the free range aren't given back.
     *
     * @param name The library's file's name; with the prefix, at most 32 bytes, or it's not found.
     * @return Its interface record, at its ELF entry, which stays mapped for the rest of the process's life; or null
     *     if there's no startup block or no such grant, the file isn't a 64-bit little-endian shared object for this
     *     machine or is cut short, it has more than LIBRARY_MAX_SEGMENTS written segments, a relocation is of another
     *     kind or outside its copies, or the free range or the kernel couldn't give the memory.
     */
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

    /**
     * Apply a library's dynamic section: its relative relocations, each within a copy, and nothing else.
     *
     * The dynamic section has to be within a copy too, so it's read from the program's own memory. Relocations
     * before one that's refused are already applied when it returns false.
     *
     * @param base The library's base: what its addresses are from, and what each relocation adds.
     * @param address Where the dynamic section is, from the library's base.
     * @param copies The library's written segments, copied, which every relocation has to be within.
     * @return True once they're all applied, or if it has none; false if the section or a relocation isn't within a
     *     copy, it has Rel, PLT or packed relocations, its Rela entries aren't LibraryRela's size, or one isn't a
     *     relative relocation.
     */
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

    /**
     * Check whether bytes are all within one of a library's copies.
     *
     * @param offset Where the bytes start, from the library's base.
     * @param bytes How many there are.
     * @param copies The library's copied segments.
     * @return True if one copy holds them all; false if none does, or there are no copies.
     */
    within_copies :: fn(offset: u64, bytes: u64, copies: LibraryCopy[]) -> bool {
        for copy in copies {
            if offset >= copy.start && offset + bytes <= copy.end {
                return true
            }
        }
        return false
    }
}

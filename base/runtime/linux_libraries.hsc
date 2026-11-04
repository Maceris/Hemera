package runtime

/*
 * Loading a typed library on Linux (libraries.hsc), where Hemera's programs have no C library to do it: the library's
 * loadable segments mapped together at an address Linux chooses, its relative relocations applied, each segment given
 * its own protection, and its interface record found at its entry, where the compiler puts it. A typed library refers
 * to nothing outside itself, so a relocation of any other kind is refused, as is anything that isn't such a library.
 */
#if OS == .Linux && TARGET_ARCH == .x86_64 {
    /** x86-64's number for pread64(2). */
    SYS_PREAD : u64 : 17
    /** x86-64's number for close(2). */
    SYS_CLOSE : u64 : 3
    /** x86-64's number for mprotect(2). */
    SYS_MPROTECT : u64 : 10
    /** x86-64's number for openat(2). */
    SYS_OPENAT : u64 : 257
    /** x86-64's number for readlinkat(2). */
    SYS_READLINKAT : u64 : 267
    /** ELF's e_machine for x86-64, EM_X86_64: a library for another machine is refused. */
    ELF_MACHINE : u16 : 62
    /** x86-64's relative relocation, R_X86_64_RELATIVE, the only kind a typed library may have. */
    RELATIVE_RELOCATION : u32 : 8
}
#else_if OS == .Linux && TARGET_ARCH == .arm64 {
    /** AArch64's number for pread64(2). */
    SYS_PREAD : u64 : 67
    /** AArch64's number for close(2). */
    SYS_CLOSE : u64 : 57
    /** AArch64's number for mprotect(2). */
    SYS_MPROTECT : u64 : 226
    /** AArch64's number for openat(2). */
    SYS_OPENAT : u64 : 56
    /** AArch64's number for readlinkat(2). */
    SYS_READLINKAT : u64 : 78
    /** ELF's e_machine for AArch64, EM_AARCH64: a library for another machine is refused. */
    ELF_MACHINE : u16 : 183
    /** AArch64's relative relocation, R_AARCH64_RELATIVE, the only kind a typed library may have. */
    RELATIVE_RELOCATION : u32 : 1027
}

#if OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {
    /** openat's and readlinkat's directory for a path relative to the working directory, -100. */
    AT_FDCWD : u64 : 0xffff_ffff_ffff_ff9c
    /** mmap's flag to map at exactly the address given, replacing what's there. */
    MAP_FIXED : u64 : 0x10
    /** mmap's protection for memory that can't be touched at all: reserved addresses. */
    PROT_NONE : u64 : 0
    /** The size of a page in bytes, which segments are mapped and protected in whole numbers of. */
    PAGE : u64 : 4096
    /** A program header's type for a segment to load. */
    PT_LOAD : u32 : 1
    /** A program header's type for the dynamic section, with the relocations' whereabouts. */
    PT_DYNAMIC : u32 : 2
    /** The dynamic section's tag that ends it. */
    DT_NULL : u64 : 0
    /** The dynamic section's tag for the address of the Rela relocations. */
    DT_RELA : u64 : 7
    /** The dynamic section's tag for the size of the Rela relocations, in bytes. */
    DT_RELASZ : u64 : 8
    /** The dynamic section's tag for the size of one Rela relocation, in bytes. */
    DT_RELAENT : u64 : 9
    /** The dynamic section's tag for Rel relocations, without addends, which a typed library doesn't have. */
    DT_REL : u64 : 17
    /** The dynamic section's tag for the procedure linkage table's relocations, which a typed library doesn't have. */
    DT_JMPREL : u64 : 23
    /** The dynamic section's tag for packed relative relocations, which a typed library doesn't have. */
    DT_RELR : u64 : 36
    /**
     * The bytes of the file's start read for its header and program headers, which all have to be among them: a
     * library whose program headers end past them is refused.
     */
    HEADER_BYTES : usize : 4096

    /** An ELF64 file's header, Elf64_Ehdr, as it is at the file's start. */
    ElfHeader :: struct {
        /** e_ident: the magic "\x7fELF", the class (2 for 64-bit), the byte order (1 for little-endian), and more. */
        ident : u8[16],
        /** e_type: 3, ET_DYN, for a shared object, the only one loaded. */
        type : u16,
        /** e_machine: the architecture, which has to be ELF_MACHINE. */
        machine : u16,
        /** e_version: the ELF version, not checked. */
        version : u32,
        /** e_entry: the entry's address, relative to the library's base, where the interface record is. */
        entry : u64,
        /** e_phoff: the program headers' offset in the file, in bytes. */
        program_headers : u64,
        /** e_shoff: the section headers' offset in the file, in bytes; not used. */
        section_headers : u64,
        /** e_flags: the architecture's flags; not used. */
        flags : u32,
        /** e_ehsize: this header's size in bytes; not checked. */
        header_size : u16,
        /** e_phentsize: a program header's size in bytes, which has to be ProgramHeader's. */
        program_header_size : u16,
        /** e_phnum: how many program headers there are. */
        program_header_count : u16,
        /** e_shentsize: a section header's size in bytes; not used. */
        section_header_size : u16,
        /** e_shnum: how many section headers there are; not used. */
        section_header_count : u16,
        /** e_shstrndx: the index of the section names' section; not used. */
        section_names : u16,
    }

    /** An ELF64 program header, Elf64_Phdr: a segment, or something about the file for its loader. */
    ProgramHeader :: struct {
        /** p_type: what the header describes, like PT_LOAD or PT_DYNAMIC. */
        type : u32,
        /** p_flags: a segment's protection, PF_X (1), PF_W (2) and PF_R (4). */
        flags : u32,
        /** p_offset: where the segment's bytes are in the file, in bytes. */
        offset : u64,
        /** p_vaddr: where the segment goes, relative to the library's base. */
        address : u64,
        /** p_paddr: a physical address, not used. */
        physical : u64,
        /** p_filesz: how many of the segment's bytes are in the file. */
        file_size : u64,
        /** p_memsz: the segment's size in memory, in bytes; past file_size, it's zero. */
        memory_size : u64,
        /** p_align: the segment's alignment; not used, since segments are mapped by page. */
        alignment : u64,
    }

    /** An ELF64 relocation with an addend, Elf64_Rela. */
    Rela :: struct {
        /** r_offset: the 8 bytes it changes, relative to the library's base. */
        offset : u64,
        /** r_info: its kind in the low 32 bits, and its symbol, which a relative one doesn't have, in the high 32. */
        info : u64,
        /** r_addend: for a relative one, the address relative to the library's base that's stored. */
        addend : i64,
    }

    /**
     * Load a typed library: map its segments, apply its relocations, protect each segment as it asks, and find its
     * interface record.
     *
     * Refused, giving null, is anything that isn't an ELF64, little-endian, shared object for this machine, a file
     * whose program headers aren't in its first HEADER_BYTES, or a library with a relocation that isn't relative. On
     * a failure partway, what was mapped is left mapped. A library loaded is never unloaded.
     *
     * @param name A path, if it has a / in it, opened as it is (relative to the working directory if it doesn't start
     *     with /); a bare name is looked for in the program's own directory.
     * @return The library's interface record, at its entry, valid for the rest of the process; or null if the path
     *     was too long, the file couldn't be opened, read or mapped, or it isn't a typed library.
     */
    linux_load_library :: fn(name: string) -> ptr[LibraryInterface]? {
        path : u8[4096]
        length :: library_path(name, path) or_return null
        if length >= path.count {
            return null
        }
        path[length] = 0
        descriptor :: linux_syscall(SYS_OPENAT, AT_FDCWD, cast[u64](cast[rawptr](&path[0])), 0)
        if syscall_failed(descriptor) {
            return null
        }
        defer linux_syscall(SYS_CLOSE, descriptor)
        headers : u8[HEADER_BYTES]
        if !read_exactly(descriptor, &headers[0], HEADER_BYTES, 0, true) {
            return null
        }
        elf :: cast[ptr[ElfHeader]](&headers[0])
        // An ELF64, little-endian, of this machine, a shared object
        if elf.ident[0] != 0x7f || elf.ident[1] != 0x45 || elf.ident[2] != 0x4c || elf.ident[3] != 0x46 || elf.ident[4] != 2
            || elf.ident[5] != 1 || elf.type != 3 || elf.machine != ELF_MACHINE || cast[usize](elf.program_header_size) != size_of(ProgramHeader) {
            return null
        }
        count :: cast[usize](elf.program_header_count)
        first :: cast[usize](elf.program_headers)
        if first >= headers.count || first + count * size_of(ProgramHeader) > HEADER_BYTES {
            return null
        }
        program :: view_of(cast[ptr[ProgramHeader]](&headers[first]), count)
        lowest := ~cast[u64](0)
        highest : u64 = 0
        for each in program {
            if each.type == PT_LOAD {
                start :: each.address & ~(PAGE - 1)
                end :: (each.address + each.memory_size + PAGE - 1) & ~(PAGE - 1)
                lowest = if start < lowest { start } else { lowest }
                highest = if end > highest { end } else { highest }
            }
        }
        if highest <= lowest {
            return null
        }
        // The whole span reserved, then each segment's pages made writable and filled from the file
        span :: highest - lowest
        reserved :: linux_syscall(SYS_MMAP, 0, span, PROT_NONE, MAP_PRIVATE_ANONYMOUS, 0xffff_ffff_ffff_ffff, 0)
        if syscall_failed(reserved) {
            return null
        }
        base :: reserved - lowest
        for each in program {
            if each.type != PT_LOAD {
                continue
            }
            start :: each.address & ~(PAGE - 1)
            end :: (each.address + each.memory_size + PAGE - 1) & ~(PAGE - 1)
            mapped :: linux_syscall(SYS_MMAP, base + start, end - start, PROT_READ_WRITE, MAP_PRIVATE_ANONYMOUS | MAP_FIXED,
                0xffff_ffff_ffff_ffff, 0)
            if syscall_failed(mapped) || !read_exactly(descriptor, cast[rawptr](cast[uintptr](base + each.address)),
                cast[usize](each.file_size), each.offset, false) {
                return null
            }
        }
        for each in program {
            if each.type == PT_DYNAMIC && !relocate(base, each.address) {
                return null
            }
        }
        // Each segment's own protection: PF_X is 1, PF_W 2, PF_R 4, as PROT_EXEC, PROT_WRITE and PROT_READ are 4, 2, 1
        for each in program {
            if each.type != PT_LOAD {
                continue
            }
            protection := cast[u64](0)
            protection |= if each.flags & 4 != 0 { cast[u64](1) } else { cast[u64](0) }
            protection |= if each.flags & 2 != 0 { cast[u64](2) } else { cast[u64](0) }
            protection |= if each.flags & 1 != 0 { cast[u64](4) } else { cast[u64](0) }
            start :: each.address & ~(PAGE - 1)
            end :: (each.address + each.memory_size + PAGE - 1) & ~(PAGE - 1)
            if syscall_failed(linux_syscall(SYS_MPROTECT, base + start, end - start, protection)) {
                return null
            }
        }
        return cast[ptr[LibraryInterface]](cast[uintptr](base + elf.entry))
    }

    /**
     * Find where a library is: its name as it is if it has a folder in it, else beside the program.
     *
     * Beside the program means in the directory of /proc/self/exe's target, up to and with its last /.
     *
     * @param name The library's path or bare name, as linux_load_library was given it; a / in it makes it a path.
     * @param path Where the path is written, without a terminating 0, which the caller adds if there's room.
     * @return The path's length in bytes; or None if path is empty, the program's own path couldn't be read or
     *     doesn't fit, or the whole path doesn't fit.
     */
    library_path :: fn(name: string, path: mut u8[]) -> usize? {
        if path.count == 0 {
            return null
        }
        has_folder := false
        for byte in view_of(cast[ptr[u8]](name.data), name.count) {
            has_folder = has_folder || byte == 0x2f
        }
        at : usize = 0
        if !has_folder {
            link :: u8.[0x2f, 0x70, 0x72, 0x6f, 0x63, 0x2f, 0x73, 0x65, 0x6c, 0x66, 0x2f, 0x65, 0x78, 0x65, 0]
            read :: linux_syscall(SYS_READLINKAT, AT_FDCWD, cast[u64](cast[rawptr](&link[0])), cast[u64](cast[rawptr](&path[0])),
                cast[u64](path.count))
            if syscall_failed(read) || read >= cast[u64](path.count) {
                return null
            }
            // Up to its last /, which is kept
            for i in cast[usize](0)..<cast[usize](read) {
                if i < path.count && path[i] == 0x2f {
                    at = i + 1
                }
            }
        }
        for byte in view_of(cast[ptr[u8]](name.data), name.count) {
            if at >= path.count {
                return null
            }
            path[at] = byte
            at += 1
        }
        return at
    }

    /**
     * Read bytes of a file from an offset, with pread, a read at a time until they're all read.
     *
     * The file's position isn't moved. A read interrupted by a signal fails like any other.
     *
     * @param descriptor The open file.
     * @param into Where the bytes go, room for count of them, which only has to stay valid for the call.
     * @param count How many bytes; 0 reads nothing and succeeds.
     * @param offset Where in the file to start, in bytes from its start.
     * @param short Whether the file may end first: if true, the bytes past its end are left as they were.
     * @return True if count bytes were read, or the file ended first and short is true; false if a read failed, or the
     *     file ended first and short is false.
     */
    read_exactly :: fn(descriptor: u64, into: rawptr, count: usize, offset: u64, short: bool) -> bool {
        done : usize = 0
        loop {
            if done >= count {
                return true
            }
            read :: linux_syscall(SYS_PREAD, descriptor, cast[u64](into + done), cast[u64](count - done), offset + cast[u64](done))
            if syscall_failed(read) {
                return false
            }
            if read == 0 {
                return short
            }
            done += cast[usize](read)
        }
    }

    /**
     * Apply a library's relocations, from its dynamic section: its relative relocations, and nothing else.
     *
     * Each relative relocation stores base plus its addend at its offset. The segments have to be mapped writable
     * still. On a refusal partway, the relocations before it are left applied.
     *
     * @param base The address the library was loaded at, which its addresses are relative to.
     * @param address The dynamic section's address, relative to base, from its PT_DYNAMIC header.
     * @return True if every relocation was applied, or there were none; false if the library has Rel, PLT or packed
     *     relocations, its Rela entries aren't Rela's size, or one of them isn't relative.
     */
    relocate :: fn(base: u64, address: u64) -> bool {
        relocations : u64 = 0
        bytes : u64 = 0
        entry_size := cast[u64](size_of(Rela))
        at := base + address
        loop {
            tag :: cast[ptr[u64]](cast[uintptr](at))^
            value :: cast[ptr[u64]](cast[uintptr](at + 8))^
            if tag == DT_NULL {
                break
            }
            if tag == DT_RELA {
                relocations = value
            }
            else if tag == DT_RELASZ {
                bytes = value
            }
            else if tag == DT_RELAENT {
                entry_size = value
            }
            else if tag == DT_REL || tag == DT_JMPREL || tag == DT_RELR {
                return false
            }
            at += 16
        }
        if relocations == 0 || bytes == 0 {
            return true
        }
        if entry_size != cast[u64](size_of(Rela)) {
            return false
        }
        for i in cast[u64](0)..<bytes / entry_size {
            each :: cast[ptr[Rela]](cast[uintptr](base + relocations + i * entry_size))
            if cast[u32](each.info & 0xffffffff) != RELATIVE_RELOCATION {
                return false
            }
            cast[ptr[mut u64]](cast[uintptr](base + each.offset))^ = base + cast[u64](each.addend)
        }
        return true
    }
}

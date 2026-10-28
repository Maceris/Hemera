package runtime

/*
 * Loading a typed library on Linux (libraries.hsc), where Hemera's programs have no C library to do it: the library's
 * loadable segments mapped together at an address Linux chooses, its relative relocations applied, each segment given
 * its own protection, and its interface record found at its entry, where the compiler puts it. A typed library refers
 * to nothing outside itself, so a relocation of any other kind is refused, as is anything that isn't such a library.
 */
#if OS == .Linux && TARGET_ARCH == .x86_64 {
    SYS_PREAD : u64 : 17
    SYS_CLOSE : u64 : 3
    SYS_MPROTECT : u64 : 10
    SYS_OPENAT : u64 : 257
    SYS_READLINKAT : u64 : 267
    ELF_MACHINE : u16 : 62
    RELATIVE_RELOCATION : u32 : 8
}
#else_if OS == .Linux && TARGET_ARCH == .arm64 {
    SYS_PREAD : u64 : 67
    SYS_CLOSE : u64 : 57
    SYS_MPROTECT : u64 : 226
    SYS_OPENAT : u64 : 56
    SYS_READLINKAT : u64 : 78
    ELF_MACHINE : u16 : 183
    RELATIVE_RELOCATION : u32 : 1027
}

#if OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {
    AT_FDCWD : u64 : 0xffff_ffff_ffff_ff9c
    MAP_FIXED : u64 : 0x10
    PROT_NONE : u64 : 0
    PAGE : u64 : 4096
    PT_LOAD : u32 : 1
    PT_DYNAMIC : u32 : 2
    DT_NULL : u64 : 0
    DT_RELA : u64 : 7
    DT_RELASZ : u64 : 8
    DT_RELAENT : u64 : 9
    DT_REL : u64 : 17
    DT_JMPREL : u64 : 23
    DT_RELR : u64 : 36
    // The most program headers read, and the bytes of the file's start read for them
    HEADER_BYTES : usize : 4096

    ElfHeader :: struct {
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

    ProgramHeader :: struct {
        type : u32,
        flags : u32,
        offset : u64,
        address : u64,
        physical : u64,
        file_size : u64,
        memory_size : u64,
        alignment : u64,
    }

    Rela :: struct {
        offset : u64,
        info : u64,
        addend : i64,
    }

    // A library at path, or beside the program if it's a bare name, loaded: its interface record, or null.
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

    // Where a library is: its name as it is if it has a folder in it, else beside the program. Its length in path.
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

    // count bytes of the file from offset into into: all of them, or, if short is allowed, as many as there are.
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

    // The library's dynamic section at address applied: its relative relocations, and nothing else.
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

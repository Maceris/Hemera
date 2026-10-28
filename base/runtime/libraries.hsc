package runtime

import intrinsics from "base"

/*
 * Typed libraries (docs/compilation.md, Typed Libraries). A library built on its own has an interface record: each of
 * its #export functions by name, the schema hash of its type and its address, and the ABI it was built for, the
 * calling convention's version and the schema hash of Context, which every call passes. A program that calls one has
 * an import table: for each export it calls, the library's file, the export's name and type hash, and the slot its
 * calls go through. Before main, bind_libraries loads each library the table names, checks every import against the
 * library's record, and fills its slot, or stops the program, naming the import that doesn't match. Nothing is bound
 * later, and nothing by its name alone.
 */

// The calling convention's version, which a library and the programs calling it must share.
LIBRARY_CONVENTION : u64 : 1
// "HEMERAI1", the start of every interface record.
LIBRARY_MAGIC : u64 : 0x3149_4152_454d_4548

LibraryExport :: struct {
    name : string,
    type_hash : u8[32],
    function : rawptr,
}

// A library's interface record, its symbol hemera_interface.
LibraryInterface :: struct {
    magic : u64,
    convention : u64,
    context_hash : u8[32],
    exports : LibraryExport[],
}

LibraryImport :: struct {
    // The library's file: beside the program, unless it names a folder
    library : string,
    name : string,
    type_hash : u8[32],
    slot : ptr[mut rawptr],
}

// A program's import table (intrinsics.library_imports), empty for one that calls no library.
LibraryImports :: struct {
    convention : u64,
    context_hash : u8[32],
    imports : LibraryImport[],
}

// The interface record of a library loaded, by the name it was loaded as.
LoadedLibrary :: struct {
    name : string,
    interface : ptr[LibraryInterface],
}

// The most libraries one program loads.
MAX_LIBRARIES :: 32

/*
 * Every import the program's table has bound to the export of its name in its library, checked: the library built for
 * the same calling convention and Context as the program, and the export's type the same as the import's. Stops the
 * program, saying why, if a library can't be loaded or an import doesn't match.
 */
bind_libraries :: fn() {
    table :: intrinsics.library_imports()
    if table.imports.count == 0 {
        return void
    }
    loaded : LoadedLibrary[MAX_LIBRARIES]
    loaded_count : usize = 0
    for each in table.imports {
        found : ptr[LibraryInterface]? = null
        for library, i in loaded {
            if i < loaded_count && library.name == each.library {
                found = library.interface
                break
            }
        }
        if found is_none {
            opened :: os_load_library(each.library)
            if opened is_none {
                refuse_library(each, "can't be loaded")
            }
            record :: opened or_return void
            if record.magic != LIBRARY_MAGIC {
                refuse_library(each, "has no interface record")
            }
            if record.convention != table.convention || !same_hash(record.context_hash, table.context_hash) {
                refuse_library(each, "was built for another calling convention or Context")
            }
            if loaded_count < loaded.count {
                loaded[loaded_count] = LoadedLibrary.{name = each.library, interface = record}
                loaded_count += 1
            }
            found = record
        }
        record :: found or_return void
        bound := false
        for export in record.exports {
            if export.name == each.name {
                if !same_hash(export.type_hash, each.type_hash) {
                    refuse_library(each, "exports it with another type")
                }
                each.slot^ = export.function
                bound = true
                break
            }
        }
        if !bound {
            refuse_library(each, "doesn't export it")
        }
    }
}

same_hash #no_context :: fn(a: u8[32], b: u8[32]) -> bool {
    for byte, i in a {
        if byte != b[i] {
            return false
        }
    }
    return true
}

// The program stopped, as an import can't be bound: "library: name why".
refuse_library #no_context :: fn(import: LibraryImport, why: string) #never_returns {
    buffer := output_buffer(.ERROR)
    output_text(&buffer, "can't bind ")
    output_text(&buffer, import.name)
    output_text(&buffer, " from the library ")
    output_text(&buffer, import.library)
    output_text(&buffer, ": it ")
    output_text(&buffer, why)
    output_text(&buffer, "\n")
    output_flush(&buffer)
    os_exit_process(1)
}

#if OS == .Windows {
    LoadLibraryA #foreign(KERNEL32) : fn(name: rawptr) -> rawptr : ---
    GetProcAddress #foreign(KERNEL32) : fn(module: rawptr, name: rawptr) -> rawptr : ---

    // A library loaded by Windows' loader, which looks beside the program first, and its record by name.
    os_load_library :: fn(name: string) -> ptr[LibraryInterface]? {
        path : u8[1024]
        if name.count + 1 > path.count {
            return null
        }
        for byte, i in view_of(cast[ptr[u8]](name.data), name.count) {
            if i < path.count {
                path[i] = byte
            }
        }
        path[name.count] = 0
        module :: LoadLibraryA(cast[rawptr](&path[0]))
        if module == null {
            return null
        }
        symbol :: u8.[0x68, 0x65, 0x6d, 0x65, 0x72, 0x61, 0x5f, 0x69, 0x6e, 0x74, 0x65, 0x72, 0x66, 0x61, 0x63, 0x65, 0]
        record :: GetProcAddress(module, cast[rawptr](&symbol[0]))
        if record == null {
            return null
        }
        // Windows' memory, though the name it was found by is on the stack
        return cast[ptr[LibraryInterface]](cast[uintptr](record))
    }
}
#else_if OS == .Linux {
    // Loaded by linux_libraries.hsc's loader of its own, since Hemera's Linux programs have no C library
    os_load_library :: fn(name: string) -> ptr[LibraryInterface]? {
        return linux_load_library(name)
    }
}
#else {
    // Nothing loads typed libraries here yet
    os_load_library :: fn(name: string) -> ptr[LibraryInterface]? {
        return null
    }
}

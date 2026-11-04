package runtime

import intrinsics from "base"

/*
 * Typed libraries (docs/compilation.md, Typed Libraries). A library built on its own has an interface record: each of
 * its #export functions by name, the schema hash of its type and its address, and the ABI it was built for, the
 * calling convention's version and the schema hash of Context, which every call passes. A program that calls one has
 * an import table: for each export it calls, the library's file, the export's name and type hash, and the slot its
 * calls go through. Before main, bind_libraries loads each library the table names, checks every import against the
 * library's record, and fills its slot, or stops the program, naming the import that doesn't match. Nothing is bound
 * later, and nothing by its name alone. A library's base shares the program's process state, which binding hands it.
 */

/** The calling convention's version, which a library and the programs calling it must share. */
LIBRARY_CONVENTION : u64 : 1
/** "HEMERAI2", the start of every interface record. */
LIBRARY_MAGIC : u64 : 0x3249_4152_454d_4548

/** One #export function in a library's interface record. */
LibraryExport :: struct {
    /** The function's name, as imports name it; matched exactly, bytes for bytes. */
    name : string,
    /** The schema hash of the function's type (schema.hsc), which an import's has to equal. */
    type_hash : u8[32],
    /** The function's address in the loaded library, which binding puts in each matching import's slot. */
    function : rawptr,
}

/** A library's interface record, its symbol hemera_interface. */
LibraryInterface :: struct {
    /** LIBRARY_MAGIC in a real record; anything else and binding refuses the library. */
    magic : u64,
    /** The LIBRARY_CONVENTION the library was built with, which has to be the program's. */
    convention : u64,
    /** The schema hash of Context as the library was built, which has to be the program's, as every call passes it. */
    context_hash : u8[32],
    /** Every #export function of the library, in the library's own memory. */
    exports : LibraryExport[],
    /** Where the library's intrinsics.process_state() looks: its own state at first, the program's once it's bound. */
    process_state : ptr[mut ptr[mut ProcessState]],
}

/** One export a program calls, in its import table. */
LibraryImport :: struct {
    /** The library's file: beside the program, unless it names a folder. */
    library : string,
    /** The export's name in the library. */
    name : string,
    /** The schema hash of the type the program calls the export with, which the export's has to equal. */
    type_hash : u8[32],
    /** Where the program's calls to the export go through, filled with its address by bind_libraries before main. */
    slot : ptr[mut rawptr],
}

/** A program's import table (intrinsics.library_imports), empty for one that calls no library. */
LibraryImports :: struct {
    /** The LIBRARY_CONVENTION the program was built with. */
    convention : u64,
    /** The schema hash of Context as the program was built. */
    context_hash : u8[32],
    /** Every export the program calls, in the order binding checks them. */
    imports : LibraryImport[],
}

/** The interface record of a library loaded, by the name it was loaded as. */
LoadedLibrary :: struct {
    /** The library's file, as the import table names it. */
    name : string,
    /** Its interface record, in the loaded library's memory. */
    interface : ptr[LibraryInterface],
}

/**
 * The most libraries bind_libraries remembers having loaded; a library past them is loaded again for each of its
 * imports.
 */
MAX_LIBRARIES :: 32

/**
 * Bind every import in the program's table to the export of its name in its library, checked.
 *
 * Runs before main. Each library is loaded once, while there are fewer than MAX_LIBRARIES; its record is checked to be
 * built for the same calling convention and Context as the program, and pointed at the program's process state. Each
 * export's type has to be the same as the import's. Stops the program, with exit code 1 and a message on standard
 * error saying why, if a library can't be loaded or an import doesn't match. A program with no imports does nothing.
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
            // The library's base sees the program's process state, its startup block and what it's reserved, as its own
            record.process_state^ = intrinsics.process_state()
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

/**
 * Compare two schema hashes.
 *
 * @param a One hash.
 * @param b The other.
 * @return True when all 32 bytes are the same. Not constant-time: hashes here aren't secret.
 */
same_hash #no_context :: fn(a: u8[32], b: u8[32]) -> bool {
    for byte, i in a {
        if byte != b[i] {
            return false
        }
    }
    return true
}

/**
 * Stop the program, as an import can't be bound, with exit code 1.
 *
 * It writes "can't bind name from the library library: it why" on a line of its own to standard error first.
 *
 * @param import The import that can't be bound, named in the message.
 * @param why Why not, finishing the sentence after "it", like "doesn't export it".
 */
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
    /**
     * Load a DLL with Windows' loader (kernel32's LoadLibraryA).
     *
     * @param name The DLL's path, a null-terminated ANSI string.
     * @return The module's handle, or null when it couldn't be loaded.
     */
    LoadLibraryA #foreign(KERNEL32) : fn(name: rawptr) -> rawptr : ---
    /**
     * Find an exported symbol of a loaded DLL (kernel32's GetProcAddress).
     *
     * @param module The module's handle, from LoadLibraryA.
     * @param name The symbol's name, a null-terminated ANSI string.
     * @return The symbol's address, or null when the module has no such export.
     */
    GetProcAddress #foreign(KERNEL32) : fn(module: rawptr, name: rawptr) -> rawptr : ---

    /**
     * Load a library with Windows' loader, which looks beside the program first, and find its record by name.
     *
     * The library stays loaded for the rest of the process.
     *
     * @param name The library's file, at most 1023 bytes.
     * @return Its interface record, the symbol hemera_interface, in the library's memory; or null when the name is
     *     too long, Windows couldn't load it, or it has no hemera_interface.
     */
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
    /**
     * Load a library and find its interface record, with linux_libraries.hsc's loader of its own, since Hemera's Linux
     * programs have no C library.
     *
     * @param name The library's file.
     * @return Its interface record, in the library's memory, or null when it couldn't be loaded or has none.
     */
    os_load_library :: fn(name: string) -> ptr[LibraryInterface]? {
        return linux_load_library(name)
    }
}
#else_if OS != .SlopOS {
    /**
     * Load a library and find its interface record: here nothing loads typed libraries yet; SlopOS's loader is
     * slop_os_libraries.hsc's.
     *
     * @param name The library's file, which isn't looked for.
     * @return Always null: the library can't be loaded.
     */
    os_load_library :: fn(name: string) -> ptr[LibraryInterface]? {
        return null
    }
}

package runtime

import intrinsics from "base"

/*
 * UEFI applications (docs/compilation.md, UEFI Applications): a program the firmware runs on its boot services, like a
 * bootloader. The entry is given the image's handle and the system table, which the process state keeps (uefi_image,
 * uefi_system_table). Memory comes from the boot services' pool, output goes to the console as UTF-16, standard error
 * to the firmware's standard error where it has one, and the program ends through Exit with main's result. No
 * threads, clock or random numbers yet. std's uefi package has the rest of the firmware's tables and protocols.
 */
#if OS == .UEFI {
    /**
     * EFI_STATUS, a firmware function's result: 0 for success, the high bit set for an error, and other values for
     * warnings. A usize, since the firmware's is the width of an address.
     */
    UefiStatus :: usize

    /** EFI_SUCCESS: it worked, and what a program that ends with 0 gives its caller. */
    UEFI_SUCCESS : UefiStatus : 0
    /** EFI_ABORTED, which a program that ends with anything but 0 gives its caller; the code itself isn't kept. */
    UEFI_ABORTED : UefiStatus : 0x8000000000000015
    /** EfiLoaderData, the kind of memory the pool gives a program. */
    UEFI_LOADER_DATA : u32 : 2

    /** EFI_TABLE_HEADER, at the start of each of the firmware's tables. */
    UefiTableHeader :: struct {
        /** What table it is, a 64-bit number each kind of table has its own of. */
        signature : u64,
        /** The UEFI specification's revision the table follows, its major version in the high 16 bits. */
        revision : u32,
        /** The table's size in bytes, header and all, which can be more than the runtime's struct knows of. */
        header_size : u32,
        /** The table's CRC-32, with this field as 0 while it's computed; not checked. */
        crc32 : u32,
        /** Reserved: 0. */
        reserved : u32,
    }

    /**
     * EFI_SYSTEM_TABLE, as the entry was given it: the firmware's consoles and services. Owned by the firmware, which
     * keeps it for as long as the program runs.
     */
    UefiSystemTable :: struct {
        /** The table's header. */
        header : UefiTableHeader,
        /** The firmware's vendor's name, UTF-16 ending in a 0. */
        firmware_vendor : rawptr,
        /** The firmware's own revision, as its vendor numbers them. */
        firmware_revision : u32,
        /** The console input's handle. */
        console_in_handle : rawptr,
        /** The console's EFI_SIMPLE_TEXT_INPUT_PROTOCOL, which the runtime doesn't use. */
        console_in : rawptr,
        /** The console output's handle. */
        console_out_handle : rawptr,
        /** The console's text output, where standard output goes; null if there's none. */
        console_out : ptr[UefiTextOutput],
        /** The standard error's handle. */
        standard_error_handle : rawptr,
        /** The firmware's standard error, where standard error goes; null if there's none, which means the console. */
        standard_error : ptr[UefiTextOutput],
        /** EFI_RUNTIME_SERVICES, which the runtime doesn't use. */
        runtime_services : rawptr,
        /** The boot services, for memory and for ending the program; usable only until ExitBootServices. */
        boot_services : ptr[UefiBootServices],
        /** How many entries configuration_table has. */
        table_entries : usize,
        /** The configuration tables, like ACPI's, by GUID, which the runtime doesn't use. */
        configuration_table : rawptr,
    }

    /** EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL, as far as its first two functions. */
    UefiTextOutput :: struct {
        /**
         * Reset the output device, given the protocol itself as this, and whether to test the device more thoroughly
         * as extended; not called by the runtime.
         */
        reset : fn(this: rawptr, extended: bool) -> UefiStatus #calling_convention(.c) #no_context,
        /**
         * Write text at the cursor, given the protocol itself as this and the text as UTF-16 (UCS-2) ending in a 0;
         * a line break takes a carriage return and a line feed both.
         */
        output_string : fn(this: rawptr, text: ptr[u16]) -> UefiStatus #calling_convention(.c) #no_context,
    }

    /** EFI_BOOT_SERVICES, as far as Exit, the functions the runtime doesn't call kept as addresses. */
    UefiBootServices :: struct {
        /** The table's header. */
        header : UefiTableHeader,
        /** RaiseTPL to GetMemoryMap, which the runtime doesn't call. */
        before_pool : rawptr[5],
        /**
         * AllocatePool: size bytes of memory of the kind given, like UEFI_LOADER_DATA, stored through buffer,
         * 8-byte aligned and not zeroed; EFI_SUCCESS, or an error without the memory.
         */
        allocate_pool : fn(kind: u32, size: usize, buffer: ptr[mut rawptr]) -> UefiStatus #calling_convention(.c) #no_context,
        /** FreePool: a block allocate_pool gave, given back. */
        free_pool : fn(buffer: rawptr) -> UefiStatus #calling_convention(.c) #no_context,
        /** CreateEvent to StartImage, which the runtime doesn't call. */
        before_exit : rawptr[17],
        /**
         * Exit: the image ended, giving status, and data_size bytes of data (none here) to whoever started it; it
         * doesn't return for the running image.
         */
        exit : fn(image: rawptr, status: UefiStatus, data_size: usize, data: rawptr) -> UefiStatus #calling_convention(.c) #no_context,
    }

    /**
     * Give the system table the entry was given.
     *
     * @return The firmware's system table, which it keeps for as long as the program runs; or null before the entry
     *     has stored it.
     */
    uefi_system_table #no_context :: fn() -> ptr[UefiSystemTable]? {
        table :: intrinsics.process_state().uefi_system_table
        if table == null {
            return null
        }
        return cast[ptr[UefiSystemTable]](table)
    }

    /**
     * Allocate, resize or free a block of the boot services' pool, as an AllocatorFn, for POOL_ALLOCATOR.
     *
     * The pool zeroes nothing, so each new block is zeroed here. Each block has room in front of it for where the
     * pool's block starts, so any alignment works and freeing needs only the pointer. Nothing works after
     * ExitBootServices.
     *
     * @param allocator_data Unused: the allocator has no state.
     * @param size The new block's size in bytes; 0 for no new block, only freeing old_memory.
     * @param alignment The new block's alignment, a power of two; anything up to 16 gives 16.
     * @param old_memory A block this allocator gave, to copy from and free, or null for none.
     * @param old_size old_memory's size in bytes, of which as many as fit are copied into the new block.
     * @param location Where the allocation was asked for; unused.
     * @return The new block, zeroed but for what was copied, which the caller owns until it gives it back; empty when
     *     size is 0 or on an error.
     * @return An error, or null: OutOfMemory if the pool couldn't give the block, or there's no system table yet;
     *     InvalidArgument if alignment isn't a power of two. On an error, old_memory is left as it was.
     */
    pool_allocator_function : AllocatorFn : fn(
        allocator_data: rawptr,
        size: usize,
        alignment: usize,
        old_memory: rawptr,
        old_size: usize,
        location := #caller_location,
    ) -> (mut u8[], AllocatorError?) {
        empty : mut u8[]
        services :: match uefi_system_table() {
            case Some(table) => table.boot_services
            case None => return empty, AllocatorError.OutOfMemory
        }
        result := empty
        if size > 0 {
            align :: if alignment > 16 { alignment } else { cast[usize](16) }
            if align & (align - 1) != 0 {
                return empty, AllocatorError.InvalidArgument
            }
            raw : rawptr = null
            if services.allocate_pool(UEFI_LOADER_DATA, size + align + 16, &raw) != UEFI_SUCCESS || raw == null {
                return empty, AllocatorError.OutOfMemory
            }
            start :: (cast[usize](raw) + 8 + align - 1) & ~(align - 1)
            cast[ptr[mut usize]](cast[rawptr](start - 8))^ = cast[usize](raw)
            result = view_of(cast[ptr[mut u8]](cast[rawptr](start)), size)
            intrinsics.mem_zero(cast[mut rawptr](result.data), size)
        }
        if old_memory != null {
            if size > 0 {
                intrinsics.mem_copy(cast[mut rawptr](result.data), old_memory, if old_size < size { old_size } else { size })
            }
            raw :: cast[ptr[usize]](cast[rawptr](cast[usize](old_memory) - 8))^
            _ = services.free_pool(cast[rawptr](raw))
        }
        return result, null
    }

    /** The boot services' pool, as an allocator, giving zeroed blocks of any alignment until ExitBootServices. */
    POOL_ALLOCATOR :: Allocator.{pool_allocator_function, null}

    /**
     * Write bytes to the console, or standard error to the firmware's standard error where it has one.
     *
     * Converted to UTF-16 a buffer at a time, each line feed with a carriage return before it, which the console wants;
     * a character outside the Basic Multilingual Plane, or bytes that aren't UTF-8, are written as '?'. The UTF-8 isn't
     * checked closely: a lead byte's continuation bytes are taken as they come. Nothing happens before the entry has
     * stored the system table, or without the output, and the firmware's errors are ignored.
     *
     * @param stream OUTPUT for the console; anything else for standard error.
     * @param bytes The first byte, UTF-8, which only has to stay valid for the call.
     * @param count How many bytes; 0 writes nothing.
     */
    os_write #no_context :: fn(stream: OutputStream, bytes: rawptr, count: usize) {
        table :: uefi_system_table() or_return void
        out := table.console_out
        if stream != OutputStream.OUTPUT && cast[rawptr](table.standard_error) != null {
            out = table.standard_error
        }
        if cast[rawptr](out) == null {
            return void
        }
        buffer : u16[128]
        used := cast[usize](0)
        i := cast[usize](0)
        loop {
            if i >= count {
                break
            }
            // Room for a character, a carriage return before it, and the zero after
            if used + 3 >= buffer.count {
                if used < buffer.count {
                    buffer[used] = 0
                }
                _ = out.output_string(cast[rawptr](out), &buffer[0])
                used = 0
            }
            first :: byte_at(bytes, i)
            character := cast[u32]('?')
            length := cast[usize](1)
            if first < 0x80 {
                character = cast[u32](first)
            }
            else if first & 0xe0 == 0xc0 && i + 1 < count {
                character = (cast[u32](first & 0x1f) << 6) | cast[u32](byte_at(bytes, i + 1) & 0x3f)
                length = 2
            }
            else if first & 0xf0 == 0xe0 && i + 2 < count {
                character = (cast[u32](first & 0x0f) << 12) | (cast[u32](byte_at(bytes, i + 1) & 0x3f) << 6)
                    | cast[u32](byte_at(bytes, i + 2) & 0x3f)
                length = 3
            }
            else if first & 0xf8 == 0xf0 {
                length = 4
            }
            i += length
            if character == cast[u32]('\n') && used < buffer.count {
                buffer[used] = 0x0d
                used += 1
            }
            if used < buffer.count {
                buffer[used] = if character > 0xffff { cast[u16]('?') } else { cast[u16](character) }
                used += 1
            }
        }
        if used > 0 && used < buffer.count {
            buffer[used] = 0
            _ = out.output_string(cast[rawptr](out), &buffer[0])
        }
    }

    /**
     * Read a byte, without a context.
     *
     * @param bytes Where what's read starts; nothing is checked, so the byte at index has to be readable.
     * @param index How far from bytes, in bytes; nothing is checked, so it has to be in range.
     * @return The byte at bytes + index, any value from 0 to 255.
     */
    byte_at #no_context :: fn(bytes: rawptr, index: usize) -> u8 {
        return cast[ptr[u8]](cast[rawptr](cast[usize](bytes) + index))^
    }

    /**
     * End the program through the boot services' Exit, returning to whoever started it.
     *
     * Without a system table, or if Exit returns, the program stops with a trap.
     *
     * @param code The program's result: 0 gives EFI_SUCCESS, and anything else EFI_ABORTED, the code itself lost.
     */
    os_exit_process #no_context :: fn(code: u32) #never_returns {
        match uefi_system_table() {
            case Some(table) => _ = table.boot_services.exit(intrinsics.process_state().uefi_image, if code == 0 { UEFI_SUCCESS } else { UEFI_ABORTED }, 0, null)
            case None => {}
        }
        intrinsics.trap()
    }

    /**
     * What a UEFI program's main starts with: the pool, the standard logger and assertion handler, and no clock or
     * randomness.
     */
    HOSTED_CONTEXT :: Context.{
        allocator = POOL_ALLOCATOR,
        logger = &STANDARD_LOGGER,
        log_level = .INFO,
        clock = &NO_CLOCK,
        random = &NO_RANDOM,
        assertion_handler = printing_assertion_handler,
        user_data = null,
        extensions = null,
    }
}

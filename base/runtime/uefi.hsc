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
    UefiStatus :: usize

    // EFI_SUCCESS, and EFI_ABORTED, which a program that ends with anything but 0 gives its caller
    UEFI_SUCCESS : UefiStatus : 0
    UEFI_ABORTED : UefiStatus : 0x8000000000000015
    /** EfiLoaderData, what the pool gives a program */
    UEFI_LOADER_DATA : u32 : 2

    UefiTableHeader :: struct {
        signature : u64,
        revision : u32,
        header_size : u32,
        crc32 : u32,
        reserved : u32,
    }

    /** EFI_SYSTEM_TABLE */
    UefiSystemTable :: struct {
        header : UefiTableHeader,
        firmware_vendor : rawptr,
        firmware_revision : u32,
        console_in_handle : rawptr,
        console_in : rawptr,
        console_out_handle : rawptr,
        console_out : ptr[UefiTextOutput],
        standard_error_handle : rawptr,
        standard_error : ptr[UefiTextOutput],
        runtime_services : rawptr,
        boot_services : ptr[UefiBootServices],
        table_entries : usize,
        configuration_table : rawptr,
    }

    /** EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL, as far as its first two functions */
    UefiTextOutput :: struct {
        reset : fn(this: rawptr, extended: bool) -> UefiStatus #calling_convention(.c) #no_context,
        output_string : fn(this: rawptr, text: ptr[u16]) -> UefiStatus #calling_convention(.c) #no_context,
    }

    /** EFI_BOOT_SERVICES, as far as Exit, the functions the runtime doesn't call kept as addresses */
    UefiBootServices :: struct {
        header : UefiTableHeader,
        // RaiseTPL to GetMemoryMap
        before_pool : rawptr[5],
        allocate_pool : fn(kind: u32, size: usize, buffer: ptr[mut rawptr]) -> UefiStatus #calling_convention(.c) #no_context,
        free_pool : fn(buffer: rawptr) -> UefiStatus #calling_convention(.c) #no_context,
        // CreateEvent to StartImage
        before_exit : rawptr[17],
        exit : fn(image: rawptr, status: UefiStatus, data_size: usize, data: rawptr) -> UefiStatus #calling_convention(.c) #no_context,
    }

    /** The system table the entry was given, or null before it. */
    uefi_system_table #no_context :: fn() -> ptr[UefiSystemTable]? {
        table :: intrinsics.process_state().uefi_system_table
        if table == null {
            return null
        }
        return cast[ptr[UefiSystemTable]](table)
    }

    /*
     * The boot services' pool, which zeroes nothing: each block has room in front of it for where the pool's block
     * starts, so any alignment works and freeing needs only the pointer. Nothing after ExitBootServices.
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

    POOL_ALLOCATOR :: Allocator.{pool_allocator_function, null}

    /**
     * Bytes to the console, as UTF-16 a buffer at a time, each line ended with a carriage return as well, which the
     * console wants; a character outside the Basic Multilingual Plane, or bytes that aren't UTF-8, as '?'.
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

    /** The byte at index of bytes, read without a context. */
    byte_at #no_context :: fn(bytes: rawptr, index: usize) -> u8 {
        return cast[ptr[u8]](cast[rawptr](cast[usize](bytes) + index))^
    }

    /** The program ended through the boot services' Exit, with EFI_SUCCESS for 0 and EFI_ABORTED for anything else. */
    os_exit_process #no_context :: fn(code: u32) #never_returns {
        match uefi_system_table() {
            case Some(table) => _ = table.boot_services.exit(intrinsics.process_state().uefi_image, if code == 0 { UEFI_SUCCESS } else { UEFI_ABORTED }, 0, null)
            case None => {}
        }
        intrinsics.trap()
    }

    /**
     * What a UEFI program's main starts with: the pool, the standard logger and assertion handler, and no clock or randomness.
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

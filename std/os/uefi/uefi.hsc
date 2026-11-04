package uefi

import intrinsics from "base"
import runtime from "base"

// Only for a UEFI program, as base's runtime has these only there
#if OS == .UEFI {
    /** An EFI_STATUS: SUCCESS, or another value, an error when its top bit is set. */
    Status :: runtime.UefiStatus
    /** EFI_SUCCESS: what a firmware call returns when it did what it was asked. */
    SUCCESS :: runtime.UEFI_SUCCESS
    /** EFI_BUFFER_TOO_SMALL: the buffer given was too small, and the size it needs was written back. */
    BUFFER_TOO_SMALL : Status : 0x8000000000000005
    /** EFI_NOT_FOUND: what was asked for isn't there. */
    NOT_FOUND : Status : 0x800000000000000e

    /** An EFI_GUID, which names a protocol or a configuration table. */
    Guid :: struct {
        /** The first group, 32 bits. */
        data1 : u32,
        /** The second group, 16 bits. */
        data2 : u16,
        /** The third group, 16 bits. */
        data3 : u16,
        /** The last 8 bytes, in order. */
        data4 : u8[8],
    }

    /**
     * Tell whether two GUIDs are the same.
     *
     * @param a One GUID, not null.
     * @param b The other, not null.
     * @return True if every field is the same.
     */
    same_guid :: fn(a: ptr[Guid], b: ptr[Guid]) -> bool {
        if a.data1 != b.data1 || a.data2 != b.data2 || a.data3 != b.data3 {
            return false
        }
        for byte, i in a.data4 {
            if byte != b.data4[i] {
                return false
            }
        }
        return true
    }

    /** EFI_RUNTIME_SERVICES, as far as ResetSystem, the functions before it kept as addresses. */
    RuntimeServices :: struct {
        /** The table's header: its signature, revision and size. */
        header : runtime.UefiTableHeader,
        /** GetTime to GetNextHighMonotonicCount, untyped, kept only so reset_system is where it is. */
        before_reset : rawptr[10],
        /**
         * ResetSystem: reset or turn off the machine, kind a ResetKind's value, with status and data_size bytes of
         * data for the firmware, which may be null with 0. It doesn't return.
         */
        reset_system : fn(kind: u32, status: Status, data_size: usize, data: rawptr) #calling_convention(.c) #no_context,
    }

    /** EFI_RESET_TYPE: how ResetSystem resets the machine. */
    ResetKind :: enum #backed_by(u32) {
        /** EfiResetCold: every circuit reset, as if turned off and on. */
        Cold,
        /** EfiResetWarm: the processors reset, memory kept where the platform can. */
        Warm,
        /** EfiResetShutdown: the machine turned off. */
        Shutdown,
    }

    /** EFI_ALLOCATE_TYPE: where AllocatePages may put the pages. */
    AllocateKind :: enum #backed_by(u32) {
        /** AllocateAnyPages: anywhere. */
        AnyPages,
        /** AllocateMaxAddress: at or below the address given. */
        MaxAddress,
        /** AllocateAddress: at exactly the address given. */
        Address,
    }

    /** EFI_MEMORY_TYPE: what a range of memory is, and who may use it, before and after ExitBootServices. */
    MemoryKind :: enum #backed_by(u32) {
        /** EfiReservedMemoryType: not to be used. */
        Reserved,
        /** EfiLoaderCode: a loaded application's code, the program's own. */
        LoaderCode,
        /** EfiLoaderData: a loaded application's data, and what it allocates, the program's own. */
        LoaderData,
        /** EfiBootServicesCode: the boot services' code, free once they're left. */
        BootServicesCode,
        /** EfiBootServicesData: the boot services' data, free once they're left. */
        BootServicesData,
        /** EfiRuntimeServicesCode: the runtime services' code, kept for as long as they're used. */
        RuntimeServicesCode,
        /** EfiRuntimeServicesData: the runtime services' data, kept for as long as they're used. */
        RuntimeServicesData,
        /** EfiConventionalMemory: free memory. */
        Conventional,
        /** EfiUnusableMemory: memory with errors. */
        Unusable,
        /** EfiACPIReclaimMemory: ACPI's tables, free once they've been read. */
        AcpiReclaim,
        /** EfiACPIMemoryNVS: ACPI's firmware memory, kept. */
        AcpiNvs,
        /** EfiMemoryMappedIO: device registers the runtime services use. */
        MemoryMappedIo,
        /** EfiMemoryMappedIOPortSpace: I/O ports mapped into memory. */
        MemoryMappedIoPortSpace,
        /** EfiPalCode: the processor's firmware code, kept. */
        PalCode,
        /** EfiPersistentMemory: memory that keeps its contents without power. */
        Persistent,
        /** EfiUnacceptedMemoryType: memory a confidential guest has to accept before it's used. */
        Unaccepted,
    }

    /**
     * EFI_MEMORY_DESCRIPTOR: one range of GetMemoryMap's map. The firmware's may be longer, so the map is stepped
     * through by GetMemoryMap's descriptor size, not this one's.
     */
    MemoryDescriptor :: struct {
        /** A MemoryKind's value; one this version doesn't know is best left alone. */
        kind : u32,
        /** Unused, so physical_start is aligned. */
        padding : u32,
        /** The range's first physical address, 4 KiB aligned. */
        physical_start : u64,
        /** The range's first virtual address, as SetVirtualAddressMap was given it; 0 before. */
        virtual_start : u64,
        /** The range's size, in 4 KiB pages. */
        pages : u64,
        /** The EFI_MEMORY_ bits of what the range can do: caching, protection, and EFI_MEMORY_RUNTIME. */
        attribute : u64,
    }

    /**
     * EFI_BOOT_SERVICES, the functions used here typed, the rest kept as addresses.
     *
     * They're good only until ExitBootServices succeeds; every function takes and gives what UEFI's specification
     * says, its Status SUCCESS when it did what it was asked.
     */
    BootServices :: struct {
        /** The table's header: its signature, revision and size. */
        header : runtime.UefiTableHeader,
        /** RaiseTPL, untyped. */
        raise_tpl : rawptr,
        /** RestoreTPL, untyped. */
        restore_tpl : rawptr,
        /**
         * AllocatePages: pages of 4 KiB, kind an AllocateKind's value and memory_kind a MemoryKind's; memory gives the
         * address for MaxAddress and Address, and gets the first page's address.
         */
        allocate_pages : fn(kind: u32, memory_kind: u32, pages: usize, memory: ptr[mut u64]) -> Status #calling_convention(.c) #no_context,
        /** FreePages: pages AllocatePages gave, from the first's address. */
        free_pages : fn(memory: u64, pages: usize) -> Status #calling_convention(.c) #no_context,
        /**
         * GetMemoryMap: the memory map, into map, size bytes of it; size gets the bytes the map needs, BUFFER_TOO_SMALL
         * if more than were given, key the map's key for ExitBootServices, and descriptor_size and descriptor_version
         * each descriptor's.
         */
        get_memory_map : fn(size: ptr[mut usize], map: rawptr, key: ptr[mut usize], descriptor_size: ptr[mut usize],
            descriptor_version: ptr[mut u32]) -> Status #calling_convention(.c) #no_context,
        /**
         * AllocatePool: size bytes, 8-byte aligned, of memory kind, a MemoryKind's value; buffer gets their address.
         */
        allocate_pool : fn(kind: u32, size: usize, buffer: ptr[mut rawptr]) -> Status #calling_convention(.c) #no_context,
        /** FreePool: memory AllocatePool gave. */
        free_pool : fn(buffer: rawptr) -> Status #calling_convention(.c) #no_context,
        /** CreateEvent to UninstallProtocolInterface, untyped. */
        events_and_installing : rawptr[9],
        /**
         * HandleProtocol: the protocol, by its GUID, on a handle; interface gets it, or the call fails if the handle
         * hasn't it.
         */
        handle_protocol : fn(handle: rawptr, protocol: ptr[Guid], interface: ptr[mut rawptr]) -> Status #calling_convention(.c) #no_context,
        /** Reserved to StartImage, untyped. */
        before_exit : rawptr[7],
        /**
         * Exit: the image ended with status, and data_size bytes of exit data from AllocatePool, which may be null
         * with 0. It returns only if it fails.
         */
        exit : fn(image: rawptr, status: Status, data_size: usize, data: rawptr) -> Status #calling_convention(.c) #no_context,
        /** UnloadImage, untyped. */
        unload_image : rawptr,
        /**
         * ExitBootServices: the boot services left for good, if map_key is the current memory map's; if the map
         * changed since, it fails, and the map has to be got again.
         */
        exit_boot_services : fn(image: rawptr, map_key: usize) -> Status #calling_convention(.c) #no_context,
        /** GetNextMonotonicCount, untyped. */
        get_next_monotonic_count : rawptr,
        /** Stall: wait at least this many microseconds, busy. */
        stall : fn(microseconds: usize) -> Status #calling_convention(.c) #no_context,
        /**
         * SetWatchdogTimer: the watchdog set to reset the machine after timeout seconds, 0 to turn it off, with code
         * and data_size bytes of data, which may be null with 0.
         */
        set_watchdog_timer : fn(timeout: usize, code: u64, data_size: usize, data: rawptr) -> Status #calling_convention(.c) #no_context,
        /** ConnectController to LocateHandleBuffer, untyped. */
        before_locate : rawptr[7],
        /**
         * LocateProtocol: the first instance of the protocol with the GUID; registration null, and interface gets it,
         * or NOT_FOUND if there's none.
         */
        locate_protocol : fn(protocol: ptr[Guid], registration: rawptr, interface: ptr[mut rawptr]) -> Status #calling_convention(.c) #no_context,
    }

    /** EFI_CONFIGURATION_TABLE: one of the firmware's tables, by its GUID. */
    ConfigurationTable :: struct {
        /** The GUID that says what the table is: ACPI_20_GUID, SMBIOS_GUID and the like. */
        vendor : Guid,
        /** The table, its layout what the GUID says. */
        table : rawptr,
    }

    /** EFI_LOADED_IMAGE_PROTOCOL: what the firmware knows of a loaded image, such as the program's own. */
    LoadedImage :: struct {
        /** The protocol's revision. */
        revision : u32,
        /** The handle of the image that loaded this one; null for one the firmware loaded. */
        parent : rawptr,
        /** The image's system table. */
        system_table : rawptr,
        /** The handle of the device the image was loaded from. */
        device : rawptr,
        /** The image's device path, from device's. */
        file_path : rawptr,
        /** Unused. */
        reserved : rawptr,
        /** How many bytes options has. */
        options_size : u32,
        /** The image's load options, from the boot entry: usually UTF-16 text, not zero-terminated. */
        options : rawptr,
        /** The address the image was loaded at. */
        image_base : rawptr,
        /** The image's size in memory, in bytes. */
        image_size : u64,
        /** The MemoryKind its code was loaded as. */
        code_kind : u32,
        /** The MemoryKind its data was loaded as. */
        data_kind : u32,
        /** The image's Unload function, untyped. */
        unload : rawptr,
    }

    /** EFI_INPUT_KEY: a key that isn't a character has a scan code, and unicode 0. */
    InputKey :: struct {
        /** The key's scan code, for a key that isn't a character, like an arrow; 0 for a character. */
        scan_code : u16,
        /** The character it types, in UTF-16; 0 for a key that types none. */
        unicode : u16,
    }

    /** EFI_SIMPLE_TEXT_INPUT_PROTOCOL: the console's keyboard. */
    TextInput :: struct {
        /** Reset: the input device reset, with a fuller check of it if extended. */
        reset : fn(this: ptr[TextInput], extended: bool) -> Status #calling_convention(.c) #no_context,
        /** ReadKeyStroke: the next key, taken, into key, without waiting; NOT_READY when no key is waiting. */
        read_key_stroke : fn(this: ptr[TextInput], key: ptr[mut InputKey]) -> Status #calling_convention(.c) #no_context,
        /** The event signalled when a key is waiting, untyped. */
        wait_for_key : rawptr,
    }

    /** EFI_SIMPLE_FILE_SYSTEM_PROTOCOL: a volume the firmware can read. */
    SimpleFileSystem :: struct {
        /** The protocol's revision. */
        revision : u64,
        /** OpenVolume: the volume's root directory, into root, a File which the caller closes. */
        open_volume : fn(this: ptr[SimpleFileSystem], root: ptr[mut rawptr]) -> Status #calling_convention(.c) #no_context,
    }

    /** EFI_FILE_PROTOCOL: an open file or directory. */
    File :: struct {
        /** The protocol's revision. */
        revision : u64,
        /**
         * Open: a file or directory beneath this one, into opened, a File which the caller closes; name is UTF-16, its
         * folders separated by backslashes, ending in a zero; mode FILE_READ, FILE_WRITE and FILE_CREATE ORed; and
         * attributes, for one created, like FILE_DIRECTORY.
         */
        open : fn(this: ptr[File], opened: ptr[mut rawptr], name: ptr[u16], mode: u64, attributes: u64) -> Status
            #calling_convention(.c) #no_context,
        /** Close: the file closed, and this File not used again. */
        close : fn(this: ptr[File]) -> Status #calling_convention(.c) #no_context,
        /** Delete, untyped. */
        delete : rawptr,
        /**
         * Read: at most size bytes, from the file's position, into buffer; size gets how many were read, 0 at the end.
         * Of a directory, the next entry's FileInfo.
         */
        read : fn(this: ptr[File], size: ptr[mut usize], buffer: rawptr) -> Status #calling_convention(.c) #no_context,
        /** Write: size bytes from buffer, at the file's position; size gets how many were written. */
        write : fn(this: ptr[File], size: ptr[mut usize], buffer: rawptr) -> Status #calling_convention(.c) #no_context,
        /** GetPosition, untyped. */
        get_position : rawptr,
        /** SetPosition: the file's position, in bytes from its start; 0xffffffffffffffff for its end. */
        set_position : fn(this: ptr[File], position: u64) -> Status #calling_convention(.c) #no_context,
        /**
         * GetInfo: the information kind names, like FILE_INFO_GUID's FileInfo, into buffer, size bytes of it; size
         * gets the bytes it needs, BUFFER_TOO_SMALL if more than were given.
         */
        get_info : fn(this: ptr[File], kind: ptr[Guid], size: ptr[mut usize], buffer: rawptr) -> Status #calling_convention(.c) #no_context,
        /** SetInfo, untyped. */
        set_info : rawptr,
        /** Flush: what's been written, to the device. */
        flush : fn(this: ptr[File]) -> Status #calling_convention(.c) #no_context,
    }

    /** EFI_FILE_MODE_READ: File.open's mode bit to read. */
    FILE_READ : u64 : 1
    /** EFI_FILE_MODE_WRITE: File.open's mode bit to write, which needs FILE_READ too. */
    FILE_WRITE : u64 : 2
    /** EFI_FILE_MODE_CREATE: File.open's mode bit to make the file if it isn't there, which needs both others too. */
    FILE_CREATE : u64 : 0x8000000000000000
    /** EFI_FILE_DIRECTORY: the attribute bit of a directory, in FileInfo.attribute and File.open's attributes. */
    FILE_DIRECTORY : u64 : 0x10

    /** EFI_FILE_INFO, before its name, which follows it as UTF-16 ending in a zero. */
    FileInfo :: struct {
        /** The whole structure's size in bytes, its name included. */
        size : u64,
        /** The file's size in bytes. */
        file_size : u64,
        /** How many bytes the file takes on its volume. */
        physical_size : u64,
        /** Its creation, last access and modification times, three EFI_TIMEs, kept as bytes. */
        times : u8[48],
        /** Its attribute bits, like FILE_DIRECTORY. */
        attribute : u64,
    }

    /** EFI_RNG_PROTOCOL: the firmware's random numbers. */
    Rng :: struct {
        /** GetInfo, untyped. */
        get_info : rawptr,
        /** GetRNG: length random bytes into value, by algorithm, a GUID, or null for the firmware's default. */
        get_rng : fn(this: ptr[Rng], algorithm: rawptr, length: usize, value: ptr[mut u8]) -> Status #calling_convention(.c) #no_context,
    }

    /** EFI_GRAPHICS_OUTPUT_PROTOCOL, and its mode. */
    GraphicsOutput :: struct {
        /** QueryMode, untyped. */
        query_mode : rawptr,
        /** SetMode, untyped. */
        set_mode : rawptr,
        /** Blt, untyped. */
        blt : rawptr,
        /** The mode it's in now. */
        mode : ptr[GraphicsMode],
    }

    /** EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE: a graphics output's mode now, and its frame buffer. */
    GraphicsMode :: struct {
        /** How many modes there are, numbered from 0. */
        max_mode : u32,
        /** The number of the mode it's in. */
        mode : u32,
        /** What the mode is: its size and pixels. */
        info : ptr[GraphicsModeInfo],
        /** How many bytes info has, which may be more than GraphicsModeInfo. */
        info_size : usize,
        /** The frame buffer's physical address; meaningless for a pixel_format of 3. */
        frame_buffer_base : u64,
        /** The frame buffer's size in bytes. */
        frame_buffer_size : usize,
    }

    /** EFI_GRAPHICS_OUTPUT_MODE_INFORMATION: a mode's size and pixels. */
    GraphicsModeInfo :: struct {
        /** The structure's version, 0. */
        version : u32,
        /** The width, in pixels. */
        width : u32,
        /** The height, in pixels. */
        height : u32,
        /**
         * EFI_GRAPHICS_PIXEL_FORMAT: 0 red, green, blue in bytes; 1 the other way; 2 by masks; 3 no frame buffer.
         */
        pixel_format : u32,
        /** Red's bits in a pixel, for a pixel_format of 2. */
        red_mask : u32,
        /** Green's bits in a pixel, for a pixel_format of 2. */
        green_mask : u32,
        /** Blue's bits in a pixel, for a pixel_format of 2. */
        blue_mask : u32,
        /** The bits that aren't a colour's, for a pixel_format of 2. */
        reserved_mask : u32,
        /** Pixels from the start of one row to the start of the next, at least width. */
        pixels_per_scan_line : u32,
    }

    /** EFI_MP_SERVICES_PROTOCOL, as far as listing the processors. */
    MpServices :: struct {
        /** GetNumberOfProcessors: how many processors there are, into count, and how many are enabled, into enabled. */
        get_number_of_processors : fn(this: ptr[MpServices], count: ptr[mut usize], enabled: ptr[mut usize]) -> Status
            #calling_convention(.c) #no_context,
        /** GetProcessorInfo: what processor number is, from 0 to the count less one, into info. */
        get_processor_info : fn(this: ptr[MpServices], number: usize, info: ptr[mut ProcessorInfo]) -> Status #calling_convention(.c) #no_context,
    }

    /** EFI_PROCESSOR_INFORMATION, with room for the extended information newer firmware may write after it. */
    ProcessorInfo :: struct {
        /** The local APIC ID on x86-64, MPIDR's affinity fields on AArch64. */
        id : u64,
        /** PROCESSOR_AS_BSP_BIT, PROCESSOR_ENABLED_BIT and PROCESSOR_HEALTH_STATUS_BIT: PROCESSOR_BOOT and the like. */
        status : u32,
        /** The physical package it's in. */
        package : u32,
        /** The core it is, in its package. */
        core : u32,
        /** The hardware thread it is, in its core. */
        thread : u32,
        /** Room for EFI_CPU_PHYSICAL_LOCATION2 and other extended information; not read here. */
        extended : u32[6],
    }

    /** PROCESSOR_AS_BSP_BIT: ProcessorInfo.status's bit for the processor the firmware runs on. */
    PROCESSOR_BOOT : u32 : 1
    /** PROCESSOR_ENABLED_BIT: ProcessorInfo.status's bit for a processor that's enabled. */
    PROCESSOR_ENABLED : u32 : 2

    /** EFI_LOADED_IMAGE_PROTOCOL's GUID, for LoadedImage. */
    LOADED_IMAGE_GUID :: Guid.{0x5b1b31a1, 0x9562, 0x11d2, u8.[0x8e, 0x3f, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]}
    /** EFI_SIMPLE_FILE_SYSTEM_PROTOCOL's GUID, for SimpleFileSystem. */
    SIMPLE_FILE_SYSTEM_GUID :: Guid.{0x964e5b22, 0x6459, 0x11d2, u8.[0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]}
    /** EFI_FILE_INFO_ID, for File.get_info's FileInfo. */
    FILE_INFO_GUID :: Guid.{0x09576e92, 0x6d3f, 0x11d2, u8.[0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]}
    /** EFI_RNG_PROTOCOL's GUID, for Rng. */
    RNG_GUID :: Guid.{0x3152bca5, 0xeade, 0x433d, u8.[0x86, 0x2e, 0xc0, 0x1c, 0xdc, 0x29, 0x1f, 0x44]}
    /** EFI_GRAPHICS_OUTPUT_PROTOCOL's GUID, for GraphicsOutput. */
    GRAPHICS_OUTPUT_GUID :: Guid.{0x9042a9de, 0x23dc, 0x4a38, u8.[0x96, 0xfb, 0x7a, 0xde, 0xd0, 0x80, 0x51, 0x6a]}
    /** EFI_MP_SERVICES_PROTOCOL's GUID, for MpServices. */
    MP_SERVICES_GUID :: Guid.{0x3fdda605, 0xa76e, 0x4f46, u8.[0xad, 0x29, 0x12, 0xf4, 0x53, 0x1b, 0x3d, 0x08]}
    // Configuration tables
    /** The configuration table of ACPI 2.0 and later's RSDP. */
    ACPI_20_GUID :: Guid.{0x8868e871, 0xe4f1, 0x11d3, u8.[0xbc, 0x22, 0x00, 0x80, 0xc7, 0x3c, 0x88, 0x81]}
    /** The configuration table of ACPI 1.0's RSDP. */
    ACPI_10_GUID :: Guid.{0xeb9d2d30, 0x2d88, 0x11d3, u8.[0x9a, 0x16, 0x00, 0x90, 0x27, 0x3f, 0xc1, 0x4d]}
    /** The configuration table of SMBIOS's 32-bit entry point. */
    SMBIOS_GUID :: Guid.{0xeb9d2d31, 0x2d88, 0x11d3, u8.[0x9a, 0x16, 0x00, 0x90, 0x27, 0x3f, 0xc1, 0x4d]}
    /** The configuration table of SMBIOS 3's 64-bit entry point. */
    SMBIOS3_GUID :: Guid.{0xf2fd1544, 0x9794, 0x4a2c, u8.[0x99, 0x2e, 0xe5, 0xbb, 0xcf, 0x20, 0xe3, 0x94]}
    /** The configuration table of the flattened device tree, on machines that have one. */
    DEVICE_TREE_GUID :: Guid.{0xb1b621d5, 0xf19c, 0x41a5, u8.[0x83, 0x0b, 0xd9, 0x15, 0x2c, 0x69, 0xaa, 0xe0]}

    /**
     * Fetch the system table the program was started with.
     *
     * @return The table, the firmware's, good for the program's run; its boot services are good only until they're
     *     left. Null before the entry has kept it.
     */
    system_table :: fn() -> ptr[runtime.UefiSystemTable]? {
        return runtime.uefi_system_table()
    }

    /**
     * Fetch the program's image handle, which the entry was given, for the calls that take it, like Exit and
     * ExitBootServices.
     *
     * @return The handle; null before the entry has kept it.
     */
    image :: fn() -> rawptr {
        return intrinsics.process_state().uefi_image
    }

    /**
     * Fetch the boot services.
     *
     * @return The boot services' table, good until ExitBootServices succeeds, and not to be called after; null if
     *     there's no system table yet.
     */
    boot_services :: fn() -> ptr[BootServices]? {
        table :: system_table() or_return null
        return cast[ptr[BootServices]](cast[rawptr](table.boot_services))
    }

    /**
     * Fetch the runtime services, which stay after the boot services are left.
     *
     * @return The runtime services' table; null if there's no system table yet, or it has no runtime services.
     */
    runtime_services :: fn() -> ptr[RuntimeServices]? {
        table :: system_table() or_return null
        if table.runtime_services == null {
            return null
        }
        return cast[ptr[RuntimeServices]](table.runtime_services)
    }

    /**
     * View the firmware's configuration tables: ACPI's, SMBIOS's, the device tree's, by their GUIDs.
     *
     * @return The tables, in the firmware's memory, not copied; empty if there's no system table yet, or it lists
     *     none.
     */
    configuration_tables :: fn() -> ConfigurationTable[] {
        none : ConfigurationTable[]
        table :: system_table() or_return none
        if table.configuration_table == null {
            return none
        }
        return view_of(cast[ptr[ConfigurationTable]](table.configuration_table), table.table_entries)
    }

    /**
     * Find a configuration table by its GUID.
     *
     * @param guid The GUID of the table wanted, like ACPI_20_GUID.
     * @return The first table with it, in the firmware's memory, its layout what the GUID says; null if there's none.
     */
    configuration_table :: fn(guid: Guid) -> rawptr? {
        wanted := guid
        for &entry in configuration_tables() {
            if same_guid(&entry.vendor, &wanted) {
                return entry.table
            }
        }
        return null
    }

    /**
     * Find a protocol on a handle, through the boot services' HandleProtocol.
     *
     * @tparam T The protocol's type, which has to be the one guid names; nothing checks it.
     * @param handle The handle, like the program's image.
     * @param guid The protocol's GUID, like LOADED_IMAGE_GUID.
     * @return The protocol, the firmware's, good while the boot services are; null if the handle hasn't it, or there
     *     are no boot services.
     */
    protocol_of :: fn[T](handle: rawptr, guid: Guid) -> ptr[T]? {
        services :: boot_services() or_return null
        wanted := guid
        found : rawptr = null
        if services.handle_protocol(handle, &wanted, &found) != SUCCESS || found == null {
            return null
        }
        return cast[ptr[T]](found)
    }

    /**
     * Find the first instance of a protocol, through the boot services' LocateProtocol.
     *
     * @tparam T The protocol's type, which has to be the one guid names; nothing checks it.
     * @param guid The protocol's GUID, like GRAPHICS_OUTPUT_GUID.
     * @return The protocol, the firmware's, good while the boot services are; null if there's none, or there are no
     *     boot services.
     */
    locate :: fn[T](guid: Guid) -> ptr[T]? {
        services :: boot_services() or_return null
        wanted := guid
        found : rawptr = null
        if services.locate_protocol(&wanted, null, &found) != SUCCESS || found == null {
            return null
        }
        return cast[ptr[T]](found)
    }

    /**
     * Take a key the console's input has waiting, without waiting for one.
     *
     * @return The key; null if none is waiting, the console has no input, there's no system table, or reading failed.
     */
    key_waiting :: fn() -> InputKey? {
        table :: system_table() or_return null
        if table.console_in == null {
            return null
        }
        input :: cast[ptr[TextInput]](table.console_in)
        key := InputKey.{}
        if input.read_key_stroke(input, &key) != SUCCESS {
            return null
        }
        return key
    }

    /**
     * Reset the machine, or turn it off, through the runtime services' ResetSystem.
     *
     * @param kind How: a cold or warm reset, or turned off. Without runtime services, or if the firmware returns, it
     *     traps instead.
     */
    reset :: fn(kind: ResetKind) #never_returns {
        match runtime_services() {
            case Some(services) => services.reset_system(cast[u32](kind), SUCCESS, 0, null)
            case None => {}
        }
        intrinsics.trap()
    }
}

package uefi

import intrinsics from "base"
import runtime from "base"

// Only for a UEFI program, as base's runtime has these only there
#if OS == .UEFI {
    Status :: runtime.UefiStatus
    SUCCESS :: runtime.UEFI_SUCCESS
    // EFI_BUFFER_TOO_SMALL and EFI_NOT_FOUND, which callers act on
    BUFFER_TOO_SMALL : Status : 0x8000000000000005
    NOT_FOUND : Status : 0x800000000000000e

    // An EFI_GUID, which names a protocol or a configuration table.
    Guid :: struct {
        data1 : u32,
        data2 : u16,
        data3 : u16,
        data4 : u8[8],
    }

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

    // EFI_RUNTIME_SERVICES, as far as ResetSystem, the functions before it kept as addresses
    RuntimeServices :: struct {
        header : runtime.UefiTableHeader,
        // GetTime to GetNextHighMonotonicCount
        before_reset : rawptr[10],
        reset_system : fn(kind: u32, status: Status, data_size: usize, data: rawptr) #calling_convention(.c) #no_context,
    }

    // EFI_RESET_TYPE
    ResetKind :: enum #backed_by(u32) {
        Cold,
        Warm,
        Shutdown,
    }

    // EFI_ALLOCATE_TYPE
    AllocateKind :: enum #backed_by(u32) {
        AnyPages,
        MaxAddress,
        Address,
    }

    // EFI_MEMORY_TYPE
    MemoryKind :: enum #backed_by(u32) {
        Reserved,
        LoaderCode,
        LoaderData,
        BootServicesCode,
        BootServicesData,
        RuntimeServicesCode,
        RuntimeServicesData,
        Conventional,
        Unusable,
        AcpiReclaim,
        AcpiNvs,
        MemoryMappedIo,
        MemoryMappedIoPortSpace,
        PalCode,
        Persistent,
        Unaccepted,
    }

    // EFI_MEMORY_DESCRIPTOR; the firmware's may be longer (GetMemoryMap's descriptor size)
    MemoryDescriptor :: struct {
        kind : u32,
        padding : u32,
        physical_start : u64,
        virtual_start : u64,
        pages : u64,
        attribute : u64,
    }

    // EFI_BOOT_SERVICES, the functions used here typed, the rest kept as addresses
    BootServices :: struct {
        header : runtime.UefiTableHeader,
        raise_tpl : rawptr,
        restore_tpl : rawptr,
        allocate_pages : fn(kind: u32, memory_kind: u32, pages: usize, memory: ptr[mut u64]) -> Status #calling_convention(.c) #no_context,
        free_pages : fn(memory: u64, pages: usize) -> Status #calling_convention(.c) #no_context,
        get_memory_map : fn(size: ptr[mut usize], map: rawptr, key: ptr[mut usize], descriptor_size: ptr[mut usize],
            descriptor_version: ptr[mut u32]) -> Status #calling_convention(.c) #no_context,
        allocate_pool : fn(kind: u32, size: usize, buffer: ptr[mut rawptr]) -> Status #calling_convention(.c) #no_context,
        free_pool : fn(buffer: rawptr) -> Status #calling_convention(.c) #no_context,
        // CreateEvent to UninstallProtocolInterface
        events_and_installing : rawptr[9],
        handle_protocol : fn(handle: rawptr, protocol: ptr[Guid], interface: ptr[mut rawptr]) -> Status #calling_convention(.c) #no_context,
        // Reserved to StartImage
        before_exit : rawptr[7],
        exit : fn(image: rawptr, status: Status, data_size: usize, data: rawptr) -> Status #calling_convention(.c) #no_context,
        unload_image : rawptr,
        exit_boot_services : fn(image: rawptr, map_key: usize) -> Status #calling_convention(.c) #no_context,
        get_next_monotonic_count : rawptr,
        stall : fn(microseconds: usize) -> Status #calling_convention(.c) #no_context,
        set_watchdog_timer : fn(timeout: usize, code: u64, data_size: usize, data: rawptr) -> Status #calling_convention(.c) #no_context,
        // ConnectController to LocateHandleBuffer
        before_locate : rawptr[7],
        locate_protocol : fn(protocol: ptr[Guid], registration: rawptr, interface: ptr[mut rawptr]) -> Status #calling_convention(.c) #no_context,
    }

    // EFI_CONFIGURATION_TABLE
    ConfigurationTable :: struct {
        vendor : Guid,
        table : rawptr,
    }

    // EFI_LOADED_IMAGE_PROTOCOL
    LoadedImage :: struct {
        revision : u32,
        parent : rawptr,
        system_table : rawptr,
        device : rawptr,
        file_path : rawptr,
        reserved : rawptr,
        options_size : u32,
        options : rawptr,
        image_base : rawptr,
        image_size : u64,
        code_kind : u32,
        data_kind : u32,
        unload : rawptr,
    }

    // EFI_SIMPLE_FILE_SYSTEM_PROTOCOL
    SimpleFileSystem :: struct {
        revision : u64,
        // root's a File, which the caller closes
        open_volume : fn(this: ptr[SimpleFileSystem], root: ptr[mut rawptr]) -> Status #calling_convention(.c) #no_context,
    }

    // EFI_FILE_PROTOCOL
    File :: struct {
        revision : u64,
        // opened's a File, which the caller closes; name is UTF-16, its folders separated by backslashes, ending in a zero
        open : fn(this: ptr[File], opened: ptr[mut rawptr], name: ptr[u16], mode: u64, attributes: u64) -> Status
            #calling_convention(.c) #no_context,
        close : fn(this: ptr[File]) -> Status #calling_convention(.c) #no_context,
        delete : rawptr,
        read : fn(this: ptr[File], size: ptr[mut usize], buffer: rawptr) -> Status #calling_convention(.c) #no_context,
        write : fn(this: ptr[File], size: ptr[mut usize], buffer: rawptr) -> Status #calling_convention(.c) #no_context,
        get_position : rawptr,
        set_position : fn(this: ptr[File], position: u64) -> Status #calling_convention(.c) #no_context,
        get_info : fn(this: ptr[File], kind: ptr[Guid], size: ptr[mut usize], buffer: rawptr) -> Status #calling_convention(.c) #no_context,
        set_info : rawptr,
        flush : fn(this: ptr[File]) -> Status #calling_convention(.c) #no_context,
    }

    // EFI_FILE_MODE_READ, _WRITE and _CREATE
    FILE_READ : u64 : 1
    FILE_WRITE : u64 : 2
    FILE_CREATE : u64 : 0x8000000000000000
    // EFI_FILE_DIRECTORY
    FILE_DIRECTORY : u64 : 0x10

    // EFI_FILE_INFO, before its name, which follows it as UTF-16 ending in a zero
    FileInfo :: struct {
        size : u64,
        file_size : u64,
        physical_size : u64,
        times : u8[48],
        attribute : u64,
    }

    // EFI_RNG_PROTOCOL
    Rng :: struct {
        get_info : rawptr,
        // algorithm null for the firmware's default
        get_rng : fn(this: ptr[Rng], algorithm: rawptr, length: usize, value: ptr[mut u8]) -> Status #calling_convention(.c) #no_context,
    }

    // EFI_GRAPHICS_OUTPUT_PROTOCOL, and its mode
    GraphicsOutput :: struct {
        query_mode : rawptr,
        set_mode : rawptr,
        blt : rawptr,
        mode : ptr[GraphicsMode],
    }

    GraphicsMode :: struct {
        max_mode : u32,
        mode : u32,
        info : ptr[GraphicsModeInfo],
        info_size : usize,
        frame_buffer_base : u64,
        frame_buffer_size : usize,
    }

    // EFI_GRAPHICS_PIXEL_FORMAT: 0 red, green, blue in bytes; 1 the other way; 2 by masks; 3 no frame buffer
    GraphicsModeInfo :: struct {
        version : u32,
        width : u32,
        height : u32,
        pixel_format : u32,
        red_mask : u32,
        green_mask : u32,
        blue_mask : u32,
        reserved_mask : u32,
        pixels_per_scan_line : u32,
    }

    LOADED_IMAGE_GUID :: Guid.{0x5b1b31a1, 0x9562, 0x11d2, u8.[0x8e, 0x3f, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]}
    SIMPLE_FILE_SYSTEM_GUID :: Guid.{0x964e5b22, 0x6459, 0x11d2, u8.[0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]}
    FILE_INFO_GUID :: Guid.{0x09576e92, 0x6d3f, 0x11d2, u8.[0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]}
    RNG_GUID :: Guid.{0x3152bca5, 0xeade, 0x433d, u8.[0x86, 0x2e, 0xc0, 0x1c, 0xdc, 0x29, 0x1f, 0x44]}
    GRAPHICS_OUTPUT_GUID :: Guid.{0x9042a9de, 0x23dc, 0x4a38, u8.[0x96, 0xfb, 0x7a, 0xde, 0xd0, 0x80, 0x51, 0x6a]}
    // Configuration tables
    ACPI_20_GUID :: Guid.{0x8868e871, 0xe4f1, 0x11d3, u8.[0xbc, 0x22, 0x00, 0x80, 0xc7, 0x3c, 0x88, 0x81]}
    ACPI_10_GUID :: Guid.{0xeb9d2d30, 0x2d88, 0x11d3, u8.[0x9a, 0x16, 0x00, 0x90, 0x27, 0x3f, 0xc1, 0x4d]}
    SMBIOS_GUID :: Guid.{0xeb9d2d31, 0x2d88, 0x11d3, u8.[0x9a, 0x16, 0x00, 0x90, 0x27, 0x3f, 0xc1, 0x4d]}
    SMBIOS3_GUID :: Guid.{0xf2fd1544, 0x9794, 0x4a2c, u8.[0x99, 0x2e, 0xe5, 0xbb, 0xcf, 0x20, 0xe3, 0x94]}
    DEVICE_TREE_GUID :: Guid.{0xb1b621d5, 0xf19c, 0x41a5, u8.[0x83, 0x0b, 0xd9, 0x15, 0x2c, 0x69, 0xaa, 0xe0]}

    // The system table the program was started with, or null outside a UEFI program's run.
    system_table :: fn() -> ptr[runtime.UefiSystemTable]? {
        return runtime.uefi_system_table()
    }

    // The image's handle, which the entry was given.
    image :: fn() -> rawptr {
        return intrinsics.process_state().uefi_image
    }

    // The boot services, all of them, until the program leaves them.
    boot_services :: fn() -> ptr[BootServices]? {
        table :: system_table() or_return null
        return cast[ptr[BootServices]](cast[rawptr](table.boot_services))
    }

    // The runtime services, from the system table.
    runtime_services :: fn() -> ptr[RuntimeServices]? {
        table :: system_table() or_return null
        if table.runtime_services == null {
            return null
        }
        return cast[ptr[RuntimeServices]](table.runtime_services)
    }

    // The firmware's configuration tables: ACPI's, SMBIOS's, the device tree's, by their GUIDs.
    configuration_tables :: fn() -> ConfigurationTable[] {
        none : ConfigurationTable[]
        table :: system_table() or_return none
        if table.configuration_table == null {
            return none
        }
        return view_of(cast[ptr[ConfigurationTable]](table.configuration_table), table.table_entries)
    }

    // The configuration table with guid, or null.
    configuration_table :: fn(guid: Guid) -> rawptr? {
        wanted := guid
        for &entry in configuration_tables() {
            if same_guid(&entry.vendor, &wanted) {
                return entry.table
            }
        }
        return null
    }

    // The protocol guid names on handle, or null.
    protocol_of :: fn[T](handle: rawptr, guid: Guid) -> ptr[T]? {
        services :: boot_services() or_return null
        wanted := guid
        found : rawptr = null
        if services.handle_protocol(handle, &wanted, &found) != SUCCESS || found == null {
            return null
        }
        return cast[ptr[T]](found)
    }

    // The first instance of the protocol guid names, or null.
    locate :: fn[T](guid: Guid) -> ptr[T]? {
        services :: boot_services() or_return null
        wanted := guid
        found : rawptr = null
        if services.locate_protocol(&wanted, null, &found) != SUCCESS || found == null {
            return null
        }
        return cast[ptr[T]](found)
    }

    // The machine reset or turned off, as kind says, through the runtime services.
    reset :: fn(kind: ResetKind) #never_returns {
        match runtime_services() {
            case Some(services) => services.reset_system(cast[u32](kind), SUCCESS, 0, null)
            case None => {}
        }
        intrinsics.trap()
    }
}

package uefi

import intrinsics from "base"
import runtime from "base"

// Only for a UEFI program, as base's runtime has these only there
#if OS == .UEFI {
    Status :: runtime.UefiStatus
    SUCCESS :: runtime.UEFI_SUCCESS

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

    // The system table the program was started with, or null outside a UEFI program's run.
    system_table :: fn() -> ptr[runtime.UefiSystemTable]? {
        return runtime.uefi_system_table()
    }

    // The runtime services, from the system table.
    runtime_services :: fn() -> ptr[RuntimeServices]? {
        table :: system_table() or_return null
        if table.runtime_services == null {
            return null
        }
        return cast[ptr[RuntimeServices]](table.runtime_services)
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

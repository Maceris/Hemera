/*
 * A UEFI application calling through a .c function value, as it calls the firmware's services: through the shim for
 * foreign code, which on UEFI follows Microsoft's x64 convention, with 32 bytes of shadow space below the arguments.
 * Generated, not run.
 */
package uefi_function_values

Service :: alias fn(a: u64, b: u64, c: u64, d: u64, e: u64) -> u64 #calling_convention(.c) #no_context

// Where a firmware table would give the service; never called with this one
call :: fn(service: Service) -> u64 {
    return service(1, 2, 3, 4, 5)
}

main :: fn() -> int {
    return 0
}

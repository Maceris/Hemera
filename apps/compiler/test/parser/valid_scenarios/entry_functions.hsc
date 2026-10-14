package valid_scenarios

user_entry #calling_convention(.entry) :: fn(frame: ptr[mut x86_64.RegisterFrame]) #never_returns {
    cpu : ptr[ArchCpu] : cast[ptr[ArchCpu]](x86_64.read_gs_base())
    intrinsics.set_carrier(cpu.carrier)
    dispatch(frame)
}

// An NMI handler may return
nmi_entry #calling_convention(.entry) :: fn(frame: ptr[mut x86_64.RegisterFrame]) {
    handle_nmi()
}

system_call #calling_convention(.syscall_entry) :: fn(frame: ptr[mut x86_64.RegisterFrame]) #never_returns {
    x86_64.return_to_user(frame)
}

// A generic parameter with the same name as a parameter makes it compile-time
entry_points : fn[handler](handler: (fn(frame: ptr[mut RegisterFrame]) #never_returns)) -> ptr[EntryPoints] : ---

install :: fn(idt: ptr[mut Idt]) {
    addresses :: x86_64.entry_points(user_entry)
    for address, vector in addresses.addresses {
        set_gate(idt, vector, address)
    }
}

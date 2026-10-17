package runtime

import intrinsics from "base"

/*
 * What the runtime needs from Linux, through system calls rather than a C library: memory, threads,
 * and waiting on an address. x86-64 only, so far.
 */
#if OS == .Linux && TARGET_ARCH == .x86_64 {
    import x86_64 from "base/intrinsics"

    SYS_MMAP : u64 : 9
    SYS_MUNMAP : u64 : 11
    SYS_EXIT : u64 : 60
    SYS_FUTEX : u64 : 202

    PROT_READ_WRITE : u64 : 3
    MAP_PRIVATE_ANONYMOUS : u64 : 0x22
    FUTEX_WAIT : u64 : 0
    FUTEX_WAKE : u64 : 1
    // Only this process's threads wait on it, which lets the kernel skip looking for other processes
    FUTEX_PRIVATE : u64 : 128
    PAGE_SIZE : usize : 4096

    // A system call's result is an error when it's -4095 to -1.
    syscall_failed #no_context :: fn(result: u64) -> bool {
        return result > 0xffff_ffff_ffff_f000
    }

    // Pages of memory, zeroed, or null.
    map_pages #no_context :: fn(size: usize) -> rawptr {
        result :: x86_64.syscall(SYS_MMAP, 0, cast[u64](size), PROT_READ_WRITE, MAP_PRIVATE_ANONYMOUS, 0xffff_ffff_ffff_ffff, 0)
        if syscall_failed(result) {
            return null
        }
        return cast[rawptr](result)
    }

    unmap_pages #no_context :: fn(address: rawptr, size: usize) {
        x86_64.syscall(SYS_MUNMAP, cast[u64](address), cast[u64](size))
    }

    /*
     * Memory straight from the kernel, which any thread can use: each block is pages of its own, so
     * it suits blocks of a few KiB or more, like fibers and stack segments, until there's a real
     * allocator. Each block has room in front of it for where its pages start and how many there
     * are, so any alignment works and freeing needs only the pointer. Blocks are zeroed.
     */
    pages_allocator_function : AllocatorFn : fn(
        allocator_data: rawptr,
        size: usize,
        alignment: usize,
        old_memory: rawptr,
        old_size: usize,
        location := #caller_location,
    ) -> (u8[], AllocatorError?) {
        empty : u8[]
        result := empty
        if size > 0 {
            align :: if alignment > 16 { alignment } else { cast[usize](16) }
            if align & (align - 1) != 0 {
                return empty, AllocatorError.InvalidArgument
            }
            total :: (size + align + 16 + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1)
            pages :: map_pages(total)
            if pages == null {
                return empty, AllocatorError.OutOfMemory
            }
            // At least 16 bytes in, for the header just in front
            start :: (cast[usize](pages) + 16 + align - 1) & ~(align - 1)
            cast[ptr[mut usize]](cast[rawptr](start - 16))^ = cast[usize](pages)
            cast[ptr[mut usize]](cast[rawptr](start - 8))^ = total
            result = view_of(cast[ptr[mut u8]](cast[rawptr](start)), size)
        }
        if old_memory != null {
            if size > 0 {
                intrinsics.mem_copy(cast[rawptr](result.data), old_memory, if old_size < size { old_size } else { size })
            }
            pages :: cast[ptr[usize]](cast[rawptr](cast[usize](old_memory) - 16))^
            total :: cast[ptr[usize]](cast[rawptr](cast[usize](old_memory) - 8))^
            unmap_pages(cast[rawptr](pages), total)
        }
        return result, null
    }

    PAGES_ALLOCATOR :: Allocator.{pages_allocator_function, null}

    // What a hosted program's main starts with: memory from the kernel, and otherwise MINIMAL_CONTEXT's constants.
    HOSTED_CONTEXT :: Context.{
        allocator = PAGES_ALLOCATOR,
        logger = &DISCARDING_LOGGER,
        log_level = .FATAL,
        clock = &NO_CLOCK,
        random = &NO_RANDOM,
        assertion_handler = trap_assertion_handler,
        user_data = null,
        extensions = null,
    }

    // Each thread's own stack, which Linux doesn't make for a thread clone starts.
    THREAD_STACK_SIZE : usize : 1048576
    // Room left below stack_limit on a thread's own stack, for code that runs where Hemera's doesn't.
    NATIVE_STACK_RESERVE :: 65536

    ThreadSpecificOS :: struct {
        // The thread's ID, which the kernel clears once it has exited
        tid : u32,
        // Its own stack, THREAD_STACK_SIZE bytes
        stack_memory : rawptr,
    }

    /*
     * Where a thread starts, on its new stack: its carrier block first, since every prologue reads it,
     * with its stack's limit, then its function with the context it was created with. It ends with the
     * exit system call, which ends only this thread.
     */
    linux_thread_entry #calling_convention(.c) #no_context :: fn(parameter: rawptr) {
        thread :: cast[ptr[mut Thread]](parameter)
        intrinsics.set_carrier(&thread.carrier)
        thread.carrier.native_stack_limit = cast[rawptr](cast[usize](thread.stack_memory) + NATIVE_STACK_RESERVE)
        thread.carrier.stack_limit = thread.carrier.native_stack_limit
        thread.carrier.segment_allocator = thread.starting_context.allocator
        data : any
        match thread.data {
            case Some(given) => data = given
            case None => {}
        }
        push_context thread_context from thread.starting_context {
            thread.function(data)
        }
        x86_64.syscall(SYS_EXIT, 0)
        intrinsics.trap()
    }

    // CLONE_VM, FS, FILES, SIGHAND, THREAD, SYSVSEM, PARENT_SETTID and CHILD_CLEARTID: a thread of this process.
    THREAD_CLONE_FLAGS : u64 : 0x350f00

    os_thread_start :: fn(thread #escaping : ptr[mut Thread]) -> bool {
        stack :: map_pages(THREAD_STACK_SIZE)
        if stack == null {
            return false
        }
        thread.stack_memory = stack
        top :: cast[rawptr](cast[usize](stack) + THREAD_STACK_SIZE)
        result :: x86_64.clone_thread(THREAD_CLONE_FLAGS, top, &thread.tid, &thread.tid, cast[rawptr](linux_thread_entry),
            cast[rawptr](thread))
        if result <= 0 {
            unmap_pages(stack, THREAD_STACK_SIZE)
            return false
        }
        return true
    }

    /*
     * Until the kernel has cleared the thread's ID, which it does once the thread has exited, waking
     * this. Not a private futex: the kernel's wake for it isn't.
     */
    os_thread_join :: fn(thread: ptr[mut Thread]) {
        loop {
            tid :: intrinsics.atomic_load_u32_acquire(&thread.tid)
            if tid == 0 {
                break
            }
            x86_64.syscall(SYS_FUTEX, cast[u64](cast[rawptr](&thread.tid)), FUTEX_WAIT, cast[u64](tid))
        }
        unmap_pages(thread.stack_memory, THREAD_STACK_SIZE)
    }

    wait_on_value :: fn(address: ptr[u32], expected: u32) {
        x86_64.syscall(SYS_FUTEX, cast[u64](cast[rawptr](address)), FUTEX_WAIT | FUTEX_PRIVATE, cast[u64](expected))
    }

    wake_one :: fn(address: ptr[u32]) {
        x86_64.syscall(SYS_FUTEX, cast[u64](cast[rawptr](address)), FUTEX_WAKE | FUTEX_PRIVATE, 1)
    }

    wake_all :: fn(address: ptr[u32]) {
        x86_64.syscall(SYS_FUTEX, cast[u64](cast[rawptr](address)), FUTEX_WAKE | FUTEX_PRIVATE, 0x7fff_ffff)
    }
}

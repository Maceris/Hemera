package runtime

Fiber :: struct {
    function : ThreadFunction,
    data : any?,
    stack_state : FiberStackState,
    state : FiberState,
}

/*
 * Callee-saved registers for each supported ABI.
 * Only the member for the target ABI is used, the union is just
 * big enough for the largest one.
 *
 * The intrinsics save the 128-bit registers with aligned stores,
 * so these are placed first and the union is 16-byte aligned.
 */
FiberCalleeSavedRegisters :: struct #union #align(16) {
    x86_64_sysv : struct {
        rbx, r12, r13, r14, r15 : u64,
        mxcsr : u32,
        x87_control_word : u16,
    },
    x86_64_windows : struct {
        xmm6, xmm7, xmm8, xmm9, xmm10, xmm11, xmm12, xmm13, xmm14, xmm15 : u128,
        rbx, rsi, rdi, r12, r13, r14, r15 : u64,
        mxcsr : u32,
        x87_control_word : u16,
    },
    arm64 : struct {
        x19, x20, x21, x22, x23, x24, x25, x26, x27, x28 : u64,
        // Only the low 64 bits of v8-v15 are callee-saved
        d8, d9, d10, d11, d12, d13, d14, d15 : u64,
        fpcr : u64,
    },
}

/*
 * Registers that must survive a fiber switch.
 * The compiler intrinsics read from these using fixed offsets,
 * so don't reorder them.
 */
FiberSavedRegisters :: struct #align(16) {
    stack_pointer : rawptr,
    base_pointer : rawptr,
    callee_saved : FiberCalleeSavedRegisters,
}

/*
 * The compiler intrinsics read from these using fixed offsets,
 * so don't reorder them.
 */
FiberStackState :: struct {
    /*
     * Frozen frames, laid out exactly as they were on the stack, and growing
     * downward like it.
     *
     * count is always the whole allocation (equal to capacity), and only
     * frozen_frames[frozen_low ..< count] holds frozen frames, with the
     * innermost frame (the next one to thaw) starting at frozen_low.
     * Everything below frozen_low is free space for the next freeze.
     *
     * Grow it with ensure_frozen_capacity, not the array_* functions,
     * since those would keep the frames at the low end.
     * The allocator stored in the array is used for growing and freeing it.
     */
    frozen_frames : u8[..],
    frozen_low : usize,
    /*
     * Where the innermost frozen frame continues running, just after its call
     * to fiber_freeze.
     */
    resume_address : rawptr,
    /*
     * The real return address of the outermost thawed frame, whose return
     * address slot now points at fiber_thaw_trampoline.
     *
     * null when that frame already holds its real return address
     * (i.e. it's the last frozen frame).
     *
     * fiber_freeze puts this back into the frame before freezing it, so
     * frozen frames always hold their real return addresses.
     */
    patched_return_address : rawptr,
    /*
     * The stack pointer of the scheduler on the thread currently running this
     * fiber. Every frame between the stack pointer and this address belongs to
     * the fiber.
     */
    stack_top : rawptr,
    fiber_registers : FiberSavedRegisters,
    scheduler_registers : FiberSavedRegisters,
    scheduler_return_address : rawptr,
}

FiberState :: enum {
    NotStarted,
    Running,
    Suspended,
}

FiberExit :: enum {
    Yielded,
    Finished,
}

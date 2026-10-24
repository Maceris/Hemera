package valid_scenarios

import runtime from "base"

types :: fn(
    optional: int?,
    qualified: runtime.Fiber,
    qualified_generic: ptr[runtime.CarrierBlock],
    mutable: ptr[mut int],
    callback: (fn(int) -> bool),
    sized_by_constant: ptr[Fiber][QUEUE_SIZE],
    sized_by_other_package: u8[runtime.STACK_GUARD],
    sized_twice_by_other_package: u8[2][runtime.STACK_GUARD],
) -> (found: ptr[runtime.Fiber]?, count: int?) {
    return null, null
}

FiberStore :: struct {
    current : ptr[Fiber]?,
    yield_function : fn(carrier: ptr[mut CarrierBlock])?,
    buffer : ptr[Fiber][QUEUE_SIZE],
    using runtime.Context,
}

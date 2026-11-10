package runtime

import intrinsics from "base"

/*
 * The model checker's hooks (TargetOptions.model_checked, docs/testing.md's Model Checking): in a build with the
 * option, each atomic operation of 8 bytes or fewer, each fence and each spin hint calls one of these instead of being
 * done where it is, so a model checker on the carrier (CarrierBlock.model) can choose what happens: which thread runs
 * next, and what a load reads. Without a checker, each does its operation as the hardware would, sequentially
 * consistent whatever order was asked, which is never weaker than asked. The compiler leaves this file's own atomics as
 * they are.
 */

/** What a model hook's atomic operation is, as the compiler numbers it. */
ModelOperation :: enum #backed_by(u32) {
    /** A load: what it reads is the old value. */
    Load = 0,
    /** A store of the value. */
    Store = 1,
    /** An exchange: the value stored, the old one given back. */
    Exchange = 2,
    /** The value added, wrapping; also an increment, by one. */
    Add = 3,
    /** The value subtracted, wrapping; a decrement, by one. */
    Subtract = 4,
    /** A bitwise and with the value. */
    And = 5,
    /** A bitwise or with the value. */
    Or = 6,
    /** A bitwise exclusive or with the value. */
    Xor = 7,
    /** A compare-exchange: the value stored if what's there is expected. */
    CompareExchange = 8,
    /** A compare-exchange that may fail even when what's there is expected, as a weak one may. */
    CompareExchangeWeak = 9,
}

/** An operation's memory order, from its intrinsic's name. */
ModelOrder :: enum #backed_by(u32) {
    /** _no_fence. */
    Relaxed = 0,
    /** _acquire. */
    Acquire = 1,
    /** _release. */
    Release = 2,
    /** _acquire_release. */
    AcquireRelease = 3,
    /** No suffix. */
    SequentiallyConsistent = 4,
}

/**
 * A model checker, as its carrier holds it (CarrierBlock.model): its functions and their state, #no_context, as atomics
 * are done where there's no context too; one that needs a context pushes one it keeps. They're called with the
 * carrier's model taken away, so atomics they do themselves, and those of what they call, are done as they are;
 * they put it back before returning, and may switch fibers meanwhile.
 */
ModelChecker :: struct {
    /** The checker's own state, given to each of its functions. */
    data : rawptr,
    /**
     * Do an atomic operation: what the model has it read, and what it stores.
     *
     * @param data The checker's state.
     * @param operation What's done.
     * @param order Its memory order.
     * @param width How many bytes the location has: 1, 2, 4 or 8.
     * @param address The location.
     * @param value The value stored, added and so on, zero-extended; a compare-exchange's exchange.
     * @param expected A compare-exchange's expected value, zero-extended; 0 for the others.
     * @return old What the location held before, zero-extended to 64 bits, as the operation reads it.
     * @return success For a compare-exchange, whether it stored; true for the others.
     */
    atomic : fn(data: rawptr, operation: ModelOperation, order: ModelOrder, width: u32, address: rawptr, value: u64, expected: u64)
        -> (old: u64, success: bool) #no_context,
    /**
     * Do a fence.
     *
     * @param data The checker's state.
     * @param order Its order.
     */
    fence : fn(data: rawptr, order: ModelOrder) #no_context,
    /**
     * Take a spin hint: a thread waiting for another, which the checker may switch away from.
     *
     * @param data The checker's state.
     */
    spin : fn(data: rawptr) #no_context,
}

/**
 * Do an atomic operation in a model-checked build: the carrier's model checker's, or as the hardware would without
 * one. The compiler calls it for every atomic intrinsic of 8 bytes or fewer.
 *
 * @param operation What's done, a ModelOperation's number.
 * @param order Its memory order, a ModelOrder's number.
 * @param width How many bytes the location has: 1, 2, 4 or 8.
 * @param address The location, which has to be aligned to its width.
 * @param value The value, zero-extended.
 * @param expected A compare-exchange's expected value, zero-extended.
 * @return old What the location held before, zero-extended.
 * @return success Whether a compare-exchange stored; true for the other operations.
 */
model_atomic #no_context :: fn(operation: u32, order: u32, width: u32, address: rawptr, value: u64, expected: u64) -> (old: u64, success: bool) {
    carrier :: intrinsics.carrier()
    match carrier.model {
        case Some(checker) => {
            carrier.model = null
            old, success :: checker.atomic(checker.data, cast[ModelOperation](operation), cast[ModelOrder](order), width, address, value, expected)
            carrier.model = checker
            return old, success
        }
        case None => return native_atomic(cast[ModelOperation](operation), width, address, value, expected)
    }
}

/**
 * Do a fence in a model-checked build: the carrier's model checker's, or as the hardware would without one.
 *
 * @param order Its order, a ModelOrder's number.
 */
model_fence #no_context :: fn(order: u32) {
    carrier :: intrinsics.carrier()
    match carrier.model {
        case Some(checker) => {
            carrier.model = null
            checker.fence(checker.data, cast[ModelOrder](order))
            carrier.model = checker
        }
        case None => intrinsics.fence_sequentially_consistent()
    }
}

/** Take a spin hint in a model-checked build: the carrier's model checker's, or as the hardware would without one. */
model_spin #no_context :: fn() {
    carrier :: intrinsics.carrier()
    match carrier.model {
        case Some(checker) => {
            carrier.model = null
            checker.spin(checker.data)
            carrier.model = checker
        }
        case None => intrinsics.spin_hint()
    }
}

/**
 * Do an atomic operation as the hardware would, sequentially consistent: for a model-checked build without a checker,
 * and for a checker's own memory.
 *
 * @param operation What's done.
 * @param width How many bytes the location has: 1, 2, 4 or 8; any other does nothing, and gives 0.
 * @param address The location, aligned to its width.
 * @param value The value, zero-extended; only its low width bytes are used.
 * @param expected A compare-exchange's expected value, zero-extended.
 * @return old What the location held before, zero-extended.
 * @return success Whether a compare-exchange stored; true for the others.
 */
native_atomic #no_context :: fn(operation: ModelOperation, width: u32, address: rawptr, value: u64, expected: u64) -> (old: u64, success: bool) {
    if width == 1 {
        old, success :: native_u8(operation, cast[ptr[mut u8]](address), cast[u8](value), cast[u8](expected))
        return cast[u64](old), success
    }
    if width == 2 {
        old, success :: native_u16(operation, cast[ptr[mut u16]](address), cast[u16](value), cast[u16](expected))
        return cast[u64](old), success
    }
    if width == 4 {
        old, success :: native_u32(operation, cast[ptr[mut u32]](address), cast[u32](value), cast[u32](expected))
        return cast[u64](old), success
    }
    if width == 8 {
        return native_u64(operation, cast[ptr[mut u64]](address), value, expected)
    }
    return 0, true
}

/**
 * Do an operation on a byte, as native_atomic does.
 *
 * @param operation What's done.
 * @param target The location.
 * @param value The value.
 * @param expected A compare-exchange's expected value.
 * @return old What it held before.
 * @return success Whether a compare-exchange stored; true for the others.
 */
native_u8 #no_context :: fn(operation: ModelOperation, target: ptr[mut u8], value: u8, expected: u8) -> (old: u8, success: bool) {
    match operation {
        case .Load => return intrinsics.atomic_load_u8(target), true
        case .Store => {
            intrinsics.atomic_store_u8(target, value)
            return 0, true
        }
        case .Exchange => return intrinsics.interlocked_exchange_u8(target, value), true
        case .Add => return intrinsics.interlocked_exchange_add_u8(target, value), true
        case .Subtract => return intrinsics.interlocked_exchange_add_u8(target, 0 - value), true
        case .And => return intrinsics.interlocked_and_u8(target, value), true
        case .Or => return intrinsics.interlocked_or_u8(target, value), true
        case .Xor => return intrinsics.interlocked_xor_u8(target, value), true
        case _ => return intrinsics.interlocked_compare_exchange_u8(target, value, expected)
    }
}

/**
 * Do an operation on two bytes, as native_atomic does.
 *
 * @param operation What's done.
 * @param target The location.
 * @param value The value.
 * @param expected A compare-exchange's expected value.
 * @return old What it held before.
 * @return success Whether a compare-exchange stored; true for the others.
 */
native_u16 #no_context :: fn(operation: ModelOperation, target: ptr[mut u16], value: u16, expected: u16) -> (old: u16, success: bool) {
    match operation {
        case .Load => return intrinsics.atomic_load_u16(target), true
        case .Store => {
            intrinsics.atomic_store_u16(target, value)
            return 0, true
        }
        case .Exchange => return intrinsics.interlocked_exchange_u16(target, value), true
        case .Add => return intrinsics.interlocked_exchange_add_u16(target, value), true
        case .Subtract => return intrinsics.interlocked_exchange_add_u16(target, 0 - value), true
        case .And => return intrinsics.interlocked_and_u16(target, value), true
        case .Or => return intrinsics.interlocked_or_u16(target, value), true
        case .Xor => return intrinsics.interlocked_xor_u16(target, value), true
        case _ => return intrinsics.interlocked_compare_exchange_u16(target, value, expected)
    }
}

/**
 * Do an operation on four bytes, as native_atomic does.
 *
 * @param operation What's done.
 * @param target The location.
 * @param value The value.
 * @param expected A compare-exchange's expected value.
 * @return old What it held before.
 * @return success Whether a compare-exchange stored; true for the others.
 */
native_u32 #no_context :: fn(operation: ModelOperation, target: ptr[mut u32], value: u32, expected: u32) -> (old: u32, success: bool) {
    match operation {
        case .Load => return intrinsics.atomic_load_u32(target), true
        case .Store => {
            intrinsics.atomic_store_u32(target, value)
            return 0, true
        }
        case .Exchange => return intrinsics.interlocked_exchange_u32(target, value), true
        case .Add => return intrinsics.interlocked_exchange_add_u32(target, value), true
        case .Subtract => return intrinsics.interlocked_exchange_add_u32(target, 0 - value), true
        case .And => return intrinsics.interlocked_and_u32(target, value), true
        case .Or => return intrinsics.interlocked_or_u32(target, value), true
        case .Xor => return intrinsics.interlocked_xor_u32(target, value), true
        case _ => return intrinsics.interlocked_compare_exchange_u32(target, value, expected)
    }
}

/**
 * Do an operation on eight bytes, as native_atomic does.
 *
 * @param operation What's done.
 * @param target The location.
 * @param value The value.
 * @param expected A compare-exchange's expected value.
 * @return old What it held before.
 * @return success Whether a compare-exchange stored; true for the others.
 */
native_u64 #no_context :: fn(operation: ModelOperation, target: ptr[mut u64], value: u64, expected: u64) -> (old: u64, success: bool) {
    match operation {
        case .Load => return intrinsics.atomic_load_u64(target), true
        case .Store => {
            intrinsics.atomic_store_u64(target, value)
            return 0, true
        }
        case .Exchange => return intrinsics.interlocked_exchange_u64(target, value), true
        case .Add => return intrinsics.interlocked_exchange_add_u64(target, value), true
        case .Subtract => return intrinsics.interlocked_exchange_add_u64(target, 0 - value), true
        case .And => return intrinsics.interlocked_and_u64(target, value), true
        case .Or => return intrinsics.interlocked_or_u64(target, value), true
        case .Xor => return intrinsics.interlocked_xor_u64(target, value), true
        case _ => return intrinsics.interlocked_compare_exchange_u64(target, value, expected)
    }
}

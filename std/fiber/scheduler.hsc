package fiber

import intrinsics from "base"
import runtime from "base"

/*
 * A scheduler for fibers on one carrier, the thread that runs it (docs/multitasking.md). Fibers
 * take turns in the order they were added: each runs until it yields or finishes, and a fiber
 * that yields goes to the back of the line, unless no other is waiting, when it keeps running.
 * run_fibers returns once every fiber has finished, or once should_stop is set.
 *
 *     scheduler :: fiber.create_fiber_scheduler()
 *     fiber.spawn(scheduler, worker, data)
 *     fiber.run_fibers(scheduler)
 *
 * Fibers start with a copy of the context of whoever spawned them, and are made and freed with
 * the scheduler's allocator.
 *
 * Not yet: more than one carrier, parking a fiber until something wakes it, and fibers calling
 * foreign code, which needs the native stack.
 */
FiberScheduler :: struct {
    // Fibers waiting for their turn, linked through Fiber.next, first to run first
    first : ptr[mut runtime.Fiber]?,
    last : ptr[mut runtime.Fiber]?,
    waiting : usize,
    allocator : runtime.Allocator,
    // Set, by a fiber or anyone else, to stop run_fibers once the running fiber yields or finishes
    should_stop : bool,
}

create_fiber_scheduler :: fn(allocator := context.allocator) -> ptr[mut FiberScheduler] {
    result :: runtime.new(FiberScheduler, allocator)
    result.first = null
    result.last = null
    result.waiting = 0
    result.allocator = allocator
    result.should_stop = false
    return result
}

/*
 * Make a fiber that will run function(data), and add it to the back of the line. It runs once
 * run_fibers gets to it.
 */
spawn :: fn(
    scheduler: ptr[mut FiberScheduler],
    function: runtime.ThreadFunction,
    data #escaping : any? = null,
) -> (ptr[mut runtime.Fiber]?, runtime.AllocatorError?) {
    made, error :: runtime.fiber_create(function, data, scheduler.allocator)
    match made {
        case Some(fiber) => {
            add_waiting(scheduler, fiber)
            return fiber, null
        }
        case None => return null, error
    }
}

/*
 * Run the scheduler's fibers on this thread until all have finished, or should_stop is set.
 * Called from a plain thread, not from a fiber, and not while another scheduler runs here.
 */
run_fibers :: fn(scheduler #escaping : ptr[mut FiberScheduler]) {
    {
        carrier :: intrinsics.carrier()
        if carrier.current_fiber != null || carrier.yield_function != null {
            runtime.log_error("run_fibers is being called from a fiber, or a thread already running a scheduler")
            return void
        }
    }
    /*
     * The loop itself never yields (it isn't running on a fiber), so the carrier stays the same
     * and this pointer stays valid.
     */
    carrier :: intrinsics.carrier()
    carrier.yield_function = yield
    carrier.scheduler_data = cast[rawptr](scheduler)
    defer {
        carrier.yield_function = null
        carrier.scheduler_data = null
    }
    loop {
        if scheduler.should_stop {
            break
        }
        fiber :: take_waiting(scheduler) or_break
        /*
         * fiber_start calls fiber_entry on the fiber's own first segment, which calls its function;
         * fiber_resume re-enters its frames where it suspended, nothing copied. Either comes back
         * here once the fiber suspends or its function returns.
         */
        exit := runtime.FiberExit.Finished
        if fiber.state == .NotStarted {
            exit = intrinsics.fiber_start(fiber)
        }
        else {
            exit = intrinsics.fiber_resume(fiber)
        }
        if exit == .Yielded {
            add_waiting(scheduler, fiber)
        }
        else {
            runtime.fiber_destroy(fiber, scheduler.allocator)
        }
    }
}

/*
 * Installed as the carrier's yield_function, so it's what fiber_yield calls on a fiber run by
 * this scheduler, on the fiber's own stack. fiber_yield has already checked foreign_depth and
 * no_yield_depth.
 */
yield :: fn(carrier: ptr[mut runtime.CarrierBlock]) {
    current :: carrier.current_fiber or_return void
    scheduler : ptr[FiberScheduler] : cast[ptr[FiberScheduler]](carrier.scheduler_data)
    if scheduler.waiting == 0 && !scheduler.should_stop {
        // Switching would be pointless, keep running
        return void
    }
    /*
     * Back to the scheduler's loop, which puts this fiber at the back of the line. Only "returns"
     * once the fiber is resumed, so don't use carrier or scheduler after this.
     */
    intrinsics.fiber_suspend(current)
}

/*
 * Wait until awoken, suspending the current fiber if possible.
 *
 * Returns false if the fiber couldn't be suspended (not on a fiber, foreign frames on the stack,
 * or inside a no-yield region), in which case the caller has to block the thread instead.
 */
park :: fn() -> bool {
    //TODO(ches) waiter registration, waking, and the checks fiber_yield does
    return false
}

add_waiting :: fn(scheduler: ptr[mut FiberScheduler], fiber #escaping : ptr[mut runtime.Fiber]) {
    fiber.next = null
    match scheduler.last {
        case Some(last) => last.next = fiber
        case None => scheduler.first = fiber
    }
    scheduler.last = fiber
    scheduler.waiting += 1
}

take_waiting :: fn(scheduler: ptr[mut FiberScheduler]) -> ptr[mut runtime.Fiber]? {
    fiber :: scheduler.first or_return null
    scheduler.first = fiber.next
    if scheduler.first == null {
        scheduler.last = null
    }
    fiber.next = null
    scheduler.waiting -= 1
    return fiber
}

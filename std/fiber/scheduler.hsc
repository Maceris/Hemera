package fiber

import array from "base"
import intrinsics from "base"

FIBER_LOCAL_QUEUE_SIZE :: 255
FIBER_GLOBAL_QUEUE_INTERVAL :: 31
FIBER_RUN_NEXT_CAP :: 3

FiberSchedulerGlobalData :: struct {
    global_queue : ptr[Fiber][..],
    thread_data : ptr[FiberSchedulerLocalData][..],
    should_stop : bool,
}

/*
 * One per carrier thread running the scheduler.
 * Installed as the carrier's scheduler_data, so yield can find it.
 */
FiberSchedulerLocalData :: struct {
    global_data : ptr[FiberSchedulerGlobalData],
    local_queue : FiberLocalQueue,
    run_next : ptr[Fiber]?,
    index : usize,
    tasks_since_last_global_pull : u8,
    run_next_count : u8,
}

/*
 * Make a fiber that will run function(data), with a copy of the current context.
 * It doesn't run until it's added to a scheduler's queue.
 */
create_fiber :: fn(function: ThreadFunction, data #escaping : any? = null) -> (ptr[Fiber], AllocatorError?) {
    return fiber_create(function, data)
}

create_fiber_scheduler :: fn() -> ptr[FiberSchedulerGlobalData] {
    result, _ :: new(FiberSchedulerGlobalData)
    return result
}

run_fiber_scheduler : ThreadFunction : fn(data: any) {
    if data.type != ptr[FiberSchedulerGlobalData] {
        log_error("run_fiber_scheduler expected a pointer to FiberSchedulerGlobalData, but got %", data.type)
        return void
    }
    {
        carrier :: intrinsics.carrier()
        if carrier.current_fiber != null || carrier.yield_function != null {
            log_error("run_fiber_scheduler is being called from a fiber, or a thread already running a scheduler")
            return void
        }
    }
    global_data : ptr[FiberSchedulerGlobalData] : data.value

    local_data, _ := new(FiberSchedulerLocalData)
    {
        //TODO(ches) synchronize access with a lock
        new_index :: global_data.thread_data.count
        array_add(global_data.thread_data, local_data)
        local_data.index = new_index
    }
    local_data.global_data = global_data

    /*
     * The scheduler loop itself never yields (it isn't running on a fiber),
     * so the carrier stays the same and this pointer stays valid.
     */
    carrier :: intrinsics.carrier()
    carrier.yield_function = yield
    carrier.scheduler_data = cast[rawptr](local_data)
    defer {
        carrier.yield_function = null
        carrier.scheduler_data = null
    }

    next_task : ptr[Fiber]? = null
    next_task_index : usize = 0
    exit : FiberExit

    loop {
        if global_data.global_queue.count == 0 {
            //TODO(ches) sleep
            continue
        }
        //TODO(ches) actually have a strategy for updating tasks
        //TODO(ches) grab and release locks for the queue

        next_task_index = (next_task_index + 1) % global_data.global_queue.count;
        next_task = global_data.global_queue[next_task_index]

        switch next_task.state {
            case .Running: continue
            case .Finished: continue
            case .NotStarted:
                next_task.state = .Running
                /*
                 * Calls fiber_entry on the fiber's own first segment, which calls the fiber's function.
                 * Comes back here when the fiber suspends or its function returns.
                 */
                exit = intrinsics.fiber_start(next_task)
            case .Suspended:
                next_task.state = .Running
                /*
                 * Re-enters the fiber's innermost frame where it suspended. Its outer frames are
                 * re-entered one at a time, as each inner one returns. Nothing is copied.
                 * Comes back here when the fiber suspends again or its function returns.
                 */
                exit = intrinsics.fiber_resume(next_task)
        }

        switch exit {
            case .Yielded:
                next_task.state = .Suspended
            case .Finished:
                next_task.state = .Finished
                //TODO(ches) grab and release locks for the queue
                array_remove_fast(global_data.global_queue, next_task_index)
                fiber_destroy(next_task)
        }
    }
    while !global_data.should_stop
}

/*
 * Installed as the carrier's yield_function, so it's what fiber_yield calls on a fiber
 * run by this scheduler. Runs on the fiber's own stack.
 *
 * fiber_yield has already checked foreign_depth and no_yield_depth.
 */
yield :: fn(carrier: ptr[mut CarrierBlock]) {
    current :: carrier.current_fiber or_return
    local_data : ptr[FiberSchedulerLocalData] : cast[ptr[FiberSchedulerLocalData]](carrier.scheduler_data)

    if !has_other_work(local_data) {
        // Switching would be pointless, keep running
        return void
    }

    /*
     * Switches back to this carrier's scheduler loop. Only "returns" once the fiber is resumed,
     * possibly on another carrier, so don't use carrier or local_data after this.
     */
    intrinsics.fiber_suspend(current)
}

has_other_work :: fn(local_data: ptr[FiberSchedulerLocalData]) -> bool {
    //TODO(ches) look at the local queue and run_next too, with locks
    return local_data.global_data.global_queue.count > 1
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

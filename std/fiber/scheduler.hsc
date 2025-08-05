package fiber

import intrinsics from "base"

FiberState :: enum {
    Blocked,
    Running,
    Waiting,
}

FiberScheduler :: struct {
    preemptive : bool,
}

start_fiber_scheduler :: fn() {
    //TODO(ches) do the scheduler stuff

    new_context : Context
    new_context.is_running_on_a_fiber = true

    push_context new_context {

    }
}

yield :: fn() {
    if !context.is_running_on_a_fiber {
        // Returns to the actual yield call site, yielding is not reasonable
        return void
    }
    stack_max : rawptr : get_return_address()
    stack_min : rawptr : context.fiber_base_pointer
    stack_size : uintptr : cast[uintptr](stack_max) - cast[uintptr](stack_min)
    //TODO(ches) store the stack frame contents and size

    //TODO(ches) how do the stacks return locations work now that we may have moved the stack?
    //TODO(ches) can we copy over just one frame at a time, with room for return values? How much room?

    set_return_address(stack_min)
    /*
     * Returns to where the fiber function was run from, not what called yield.
     * The actual return from the yield function, from the perspective of 
     * the function calling it, happens after the fiber is resumed.
     */
}

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

FiberSchedulerLocalData :: struct {
    global_data : ptr[FiberSchedulerGlobalData],
    local_queue : FiberQueue,
    run_next : ptr[Fiber]?,
    index : usize,
    tasks_since_last_global_pull : u8,
    run_next_count : u8,
    /*
     * When running a fiber, stores the currently executing fiber functions
     * stack frame, so that we know where to drop the stack back to when
     * yielding.
     */
    fiber_base_pointer : rawptr,
}

create_fiber :: fn(function: ThreadFunction, data: any? = null) -> ptr[Fiber] {
    result := new(Fiber)
    result.function = function
    result.data = data
    result.frozen_stack = null
    result.state = .NotStarted
}

create_fiber_scheduler :: fn() -> ptr[FiberSchedulerGlobalData] {
    result :: new(FiberSchedulerGlobalData)
}

run_fiber_scheduler : ThreadFunction : fn(data: any) {
    //TODO(ches) do the scheduler stuff
    
    if data.type != ptr[FiberSchedulerGlobalData] {
        log_error("run_fiber_scheduler expected a pointer to FiberSchedulerGlobalData, but got %", data.type)
        return void
    }
    if context.is_running_on_a_fiber {
        log_error("run_fiber_scheduler is being called from a fiber")
        return void
    }
    global_data : ptr[FiberSchedulerGlobalData] : data.value

    local_data := new(FiberSchedulerLocalData)
    {
        //TODO(ches) synchronize access with a lock
        new_index :: global_data.thread_data.count
        array_add(global_data.thread_data, local_data)
        local_data.index = new_index
    }
    local_data.global_data = global_data

    new_context : Context
    new_context.is_running_on_a_fiber = true
    new_context.fiber_data = cast[rawptr](local_data);
    new_context.fiber_yield_function = yield

    push_context new_context {
        next_task : ptr[Fiber]? = null
        next_task_index : usize = 0

        frame_size : u32
        frozen_stack : u8[]
        end_of_frozen_frame : rawptr
        size_of_frozen_frame : usize
        start_of_frozen_frame : rawptr
        next_base_address : ptr[rawptr]

        // No messing with the current stack frame after we do this
        local_data.fiber_base_pointer = intrinsics.get_stack_pointer()

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
                case .NotStarted:
                    next_task.function(next_task.data)
                case .Running: continue
                case .Suspended:
                    // Weird return address handling, only returns here after the frame returns
                    // Thaw one stack frame and "call" the function associated with it
                    {
                        frozen_stack = fiber.frozen_stack or_continue

                        if frozen_stack.count == 0 {
                            //TODO(ches) grab and release locks for the queue
                            array_remove_fast(global_data.global_queue, next_task_index)
                            free(next_task)
                            continue
                        }

                        end_of_frozen_frame = cast[rawptr](cast[uintptr](frozen_stack.data) + cast[uintptr](frozen_stack.count))
                        size_of_frozen_frame = cast[ptr[usize]](cast[uintptr](end_of_frozen_frame) - cast[uintptr](size_of(usize)))^
                        start_of_frozen_frame = cast[rawptr](cast[uintptr](end_of_frozen_frame) - cast[uintptr](size_of_frozen_frame))
                        mem_copy_non_overlapping(local_data.fiber_base_pointer, start_of_frozen_frame, size_of_frozen_frame)
                        fiber.frozen_stack.count -= size_of_frozen_frame
                        
                        // Find next frame's base address
                        if frozen_stack.count > 0 {
                            end_of_frozen_frame = cast[rawptr](cast[uintptr](frozen_stack.data) + cast[uintptr](frozen_stack.count))
                            size_of_frozen_frame = cast[ptr[usize]](cast[uintptr](end_of_frozen_frame) - cast[uintptr](size_of(usize)))^
                            start_of_frozen_frame = cast[rawptr](cast[uintptr](end_of_frozen_frame) - cast[uintptr](size_of_frozen_frame))

                            next_base_address = cast[ptr[rawptr]](cast[uintptr](local_data.fiber_base_pointer) + cast[uintptr](size_of(uintptr)))
                            next_base_address^ = cast[ptr[rawptr]](start_of_frozen_frame)^
                        }

                        set_return_address(fiber.last_frame_return_address)
                        //TODO(ches) update the return pointer of that new frame to the thaw point
                    }
            }

        }
        while !global_data.should_stop
    }
}

yield :: fn() {
    if !context.is_running_on_a_fiber {
        // Returns to the actual yield call site, yielding is not reasonable
        return void
    }
    stack_max : rawptr : intrinsics.get_stack_base_pointer()
    stack_min : rawptr : context.fiber_base_pointer
    stack_size : uintptr : cast[uintptr](stack_max) - cast[uintptr](stack_min)
    stack_bytes : usize : cast[usize](stack_size) / size_of(u8)

    frozen_stack_space : u8[] = new_array(u8, stack_bytes)
    mem_copy_non_overlapping(&frozen_stack_space, stack_min, stack_bytes)

    set_return_address(stack_min)
    /*
     * Returns to where the fiber function was run from, not what called yield.
     * The actual return from the yield function, from the perspective of 
     * the function calling it, happens after the fiber is resumed.
     */
}

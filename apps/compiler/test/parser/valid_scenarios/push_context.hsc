package valid_scenarios

push_context_overrides :: fn() {
    push_context with_arena (allocator = memory.ArenaAllocator) {
        print("arena")
    }
    push_context quieter (log_level = .WARN, allocator = make_arena(context.allocator),) {
        node := extension_node(&state)
        push_context with_state (extensions = &node) {
            print("nested")
        }
    }
}

push_whole_contexts :: fn(cpu: ptr[PerCpu], saved: Context) {
    push_context boot from runtime.MINIMAL_CONTEXT {
        print("minimal")
    }
    push_context cpu_context from cpu.context^ {
        push_context quiet (log_level = .ERROR) {
            print("nested")
        }
    }
    push_context restored from saved {
        print("saved")
    }
}

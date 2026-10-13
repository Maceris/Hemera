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

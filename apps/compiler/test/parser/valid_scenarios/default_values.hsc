package valid_scenarios

// A parameter's default value can be any expression, not just a literal.
with_defaults :: fn(size: usize, allocator := context.allocator, count := 3, total: int = COUNT * 2) {
}

caller_location :: fn(location := #caller_location) {
}

// The right side of an assignment can be a typed literal.
assign_literals :: fn(result: ptr[mut Fiber]) {
    result.resume = FiberResumeState.{}
    result.size = Size.{ width = 1, height = 2 }
}

// Definitions after the functions above are still parsed.
AFTER_DEFAULTS :: 1

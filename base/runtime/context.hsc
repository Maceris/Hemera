package runtime

/*
 * Passed implicitly to every function call. It follows the logical call chain:
 * threads and fibers get a copy of their creator's context, and it can only be
 * replaced for a scope with push_context, never modified.
 *
 * Nothing about where the code is running (which OS thread, which fiber scheduler)
 * belongs here, since a fiber can move between threads. That lives in CarrierBlock.
 */
Context :: struct {
    allocator : Allocator,
    logger : ptr[Logger],
    log_level : LogLevel,
    clock : ptr[Clock],
    random : ptr[Random],
    assertion_handler : AssertionHandler,
    // One slot for a program's own data, for programs like kernels where one owner is enough.
    user_data: rawptr,
    // Typed per-scope state from any number of libraries, see ContextExtension.
    extensions : ptr[ContextExtension]?,
}

/*
 * One link in the context's chain of extensions, which lets libraries keep their own state in
 * the context without changing its layout. See docs/multitasking.md (Context Extensions).
 *
 * Add one by pushing a context whose chain starts with a new node:
 *
 *     node := extension_node(&my_state)
 *     push_context with_state (extensions = &node) {
 *         // get_extension(MyState) finds my_state here, and in everything called from here
 *     }
 *
 * Nodes may live on the stack of the frame that pushes them. Threads and fibers created inside
 * the block get their own copy of the chain (copy_extensions), so they don't depend on that frame.
 * data itself follows the usual rule for context values: it can't point into the stack.
 */
ContextExtension :: struct {
    // What the extension is: the type data points to.
    key : type,
    data : rawptr,
    next : ptr[ContextExtension]?,
}

// A node for data, in front of the current context's chain.
extension_node :: fn[T](data: ptr[T]) -> ContextExtension {
    return ContextExtension.{T, data, context.extensions}
}

// The innermost extension of type T in the current context, if there is one.
get_extension :: fn[T](T: type) -> ptr[T]? {
    node := context.extensions
    loop {
        current :: node or_break
        if current.key == T {
            return cast[ptr[T]](current.data)
        }
        node = current.next
    }
    return null
}

/*
 * Give copy, a context saved for a new thread or fiber, its own copy of its extension chain,
 * so it doesn't point into the stack frames that pushed the nodes. The returned nodes belong
 * to the thread or fiber, and are freed with it.
 */
copy_extensions :: fn(
    copy: ptr[mut Context],
    allocator := context.allocator,
    loc := #caller_location,
) -> (ContextExtension[], AllocatorError?) {
    count : usize = 0
    walk := copy.extensions
    loop {
        node :: walk or_break
        count += 1
        walk = node.next
    }

    nodes, error :: new_array(ContextExtension, count, allocator, loc)
    if error != null || count == 0 {
        return nodes, error
    }

    source := copy.extensions
    for &node, index in nodes {
        original :: source or_break
        node^ = original^
        node.next = null
        if index + 1 < nodes.count {
            node.next = &nodes[index + 1]
        }
        source = original.next
    }
    if nodes.count > 0 {
        copy.extensions = &nodes[0]
    }
    return nodes, null
}

/*
 * A context made only of constants, for code that has to push one before it has anything real:
 * freestanding entry points, like a kernel's, before there's a heap, a logger or a clock.
 * Allocations fail, log messages are dropped, the clock has no time, asking for random bytes
 * traps, and a failed assertion traps.
 *
 *     push_context boot from runtime.MINIMAL_CONTEXT {
 *         // ...
 *     }
 */
MINIMAL_CONTEXT :: Context.{
    allocator = FAILING_ALLOCATOR,
    logger = &DISCARDING_LOGGER,
    log_level = .FATAL,
    clock = &NO_CLOCK,
    random = &NO_RANDOM,
    assertion_handler = trap_assertion_handler,
    user_data = null,
    extensions = null,
}

package runtime

/**
 * Passed implicitly to every function call. It follows the logical call chain:
 * threads and fibers get a copy of their creator's context, and it can only be
 * replaced for a scope with push_context, never modified.
 *
 * Nothing about where the code is running (which OS thread, which fiber scheduler)
 * belongs here, since a fiber can move between threads. That lives in CarrierBlock.
 */
Context :: struct {
    /** Where new, new_array and the rest allocate by default, and what they free to. */
    allocator : Allocator,
    /** Where log messages go. A pointer, so loggers with state can be shared; it has to outlive the scope it's in. */
    logger : ptr[Logger],
    /** The least severe level of message that's logged: the loggers drop messages below it. */
    log_level : LogLevel,
    /** Where the time comes from; it has to outlive the scope it's in. */
    clock : ptr[Clock],
    /** Where random bytes come from; it has to outlive the scope it's in. */
    random : ptr[Random],
    /** What a failed assertion, or running out of memory where that isn't handled, calls. */
    assertion_handler : AssertionHandler,
    /** One slot for a program's own data, for programs like kernels where one owner is enough; null when unused. */
    user_data: rawptr,
    /** Typed per-scope state from any number of libraries, see ContextExtension; null for none. */
    extensions : ptr[ContextExtension]?,
}

/**
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
    /** What the extension is: the type data points to, which get_extension looks it up by. */
    key : type,
    /** The extension's state, a value of type key; it can't point into the stack. */
    data : rawptr,
    /** The next node, further out; null at the chain's end. */
    next : ptr[ContextExtension]?,
}

/**
 * Make a node for data, in front of the current context's chain, for a push_context to start its chain with.
 *
 * @tparam T The extension's type, which becomes the node's key.
 * @param data The extension's state. Contexts can't point into the stack, so it has to be somewhere else, and it has
 *     to stay valid as long as any context, thread or fiber has the node.
 * @return The node, which the caller keeps, often on its own stack, for as long as the context it's pushed in.
 */
extension_node :: fn[T](data: ptr[T]) -> ContextExtension {
    return ContextExtension.{T, data, context.extensions}
}

/**
 * Find the innermost extension of type T in the current context.
 *
 * @tparam T The extension's type, matched exactly against each node's key.
 * @param T The extension's type.
 * @return The data of the innermost node with T for its key, or null when the chain has none.
 */
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

/**
 * Give a context saved for a new thread or fiber its own copy of its extension chain,
 * so it doesn't point into the stack frames that pushed the nodes.
 *
 * The nodes are copied in order into one array; the data they point to isn't copied.
 *
 * @param copy The saved context, whose extensions are pointed at the copy; left as it was when the chain is empty or
 *     on an error.
 * @param allocator Where the array of nodes comes from, which has to free it too.
 * @param loc The caller's location, given to the allocator.
 * @return The nodes, which belong to the thread or fiber and are freed with it; empty, needing no freeing, when the
 *     chain is empty or on an error.
 * @return The allocator's error without the memory for them, or null.
 */
copy_extensions :: fn(
    copy: ptr[mut Context],
    allocator := context.allocator,
    loc := #caller_location,
) -> (mut ContextExtension[], AllocatorError?) {
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

/**
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

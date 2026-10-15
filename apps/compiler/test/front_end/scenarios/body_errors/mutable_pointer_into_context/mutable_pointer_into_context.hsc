package mutable_pointer_into_context

import runtime from "base"

f :: fn() {
    // & on the context gives a ptr without mut
    allocator : ptr[mut runtime.Allocator] = &context.allocator
}

package runtime

import intrinsics from "base"

/*
 * The process's heap (PageHeap, process.hsc) on systems where the runtime makes its own from pages the
 * system maps: map_pages and unmap_pages are each system's, in linux.hsc and slop_os.hsc.
 */
#if (OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64)) || (OS == .SlopOS && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64)) {
    /*
     * The process's PageHeap (process.hsc), which any thread can use. Blocks are zeroed, and any
     * alignment works: above 16, a block gets pages of its own.
     */
    pages_allocator_function : AllocatorFn : fn(
        allocator_data: rawptr,
        size: usize,
        alignment: usize,
        old_memory: rawptr,
        old_size: usize,
        location := #caller_location,
    ) -> (mut u8[], AllocatorError?) {
        empty : mut u8[]
        result := empty
        if size > 0 {
            if alignment & (alignment - 1) != 0 {
                return empty, AllocatorError.InvalidArgument
            }
            block :: heap_allocate(size, alignment)
            if block == null {
                return empty, AllocatorError.OutOfMemory
            }
            result = view_of(cast[ptr[mut u8]](block), size)
        }
        if old_memory != null {
            if size > 0 {
                intrinsics.mem_copy(cast[mut rawptr](result.data), old_memory, if old_size < size { old_size } else { size })
            }
            heap_free(old_memory)
        }
        return result, null
    }

    PAGES_ALLOCATOR :: Allocator.{pages_allocator_function, null}

    // The smallest class whose blocks hold size bytes, or PAGE_HEAP_CLASSES if none does.
    heap_class #no_context :: fn(size: usize) -> usize {
        class : usize = 0
        block : usize = 16
        loop {
            if size <= block {
                return class
            }
            class += 1
            block = block * 2
        }
        while class < PAGE_HEAP_CLASSES
        return PAGE_HEAP_CLASSES
    }

    heap_lock #no_context :: fn(heap: ptr[mut PageHeap]) {
        loop {
            if intrinsics.interlocked_exchange_u32(&heap.lock, 1) == 0 {
                break
            }
            intrinsics.spin_hint()
        }
    }

    heap_unlock #no_context :: fn(heap: ptr[mut PageHeap]) {
        intrinsics.atomic_store_u32_release(&heap.lock, 0)
    }

    // size zeroed bytes, aligned to alignment (a power of two, or 0), or null without memory.
    heap_allocate #no_context :: fn(size: usize, alignment: usize) -> rawptr {
        class :: heap_class(size)
        if class >= PAGE_HEAP_CLASSES || alignment > 16 {
            // Pages of its own, with what freeing them needs in front
            align :: if alignment > 16 { alignment } else { cast[usize](16) }
            total :: (size + align + 16 + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1)
            pages :: map_pages(total)
            if pages == null {
                return null
            }
            start :: (cast[usize](pages) + 16 + align - 1) & ~(align - 1)
            cast[ptr[mut usize]](cast[rawptr](start - 16))^ = total
            cast[ptr[mut usize]](cast[rawptr](start - 8))^ = cast[usize](pages)
            return cast[rawptr](start)
        }
        heap :: &intrinsics.process_state().heap
        block_size :: (cast[usize](16) << class) + 16
        heap_lock(heap)
        if class < PAGE_HEAP_CLASSES && heap.free_lists[class] == null {
            // A new chunk of this class's blocks, each on the free list
            chunk :: map_pages(PAGE_HEAP_CHUNK)
            if chunk == null {
                heap_unlock(heap)
                return null
            }
            count :: PAGE_HEAP_CHUNK / block_size
            for i in 0..<count {
                block :: cast[ptr[mut rawptr]](cast[rawptr](cast[usize](chunk) + i * block_size))
                block^ = heap.free_lists[class]
                heap.free_lists[class] = cast[rawptr](block)
            }
        }
        header :: if class < PAGE_HEAP_CLASSES { heap.free_lists[class] } else { null }
        if class < PAGE_HEAP_CLASSES {
            heap.free_lists[class] = cast[ptr[rawptr]](header)^
        }
        heap_unlock(heap)
        cast[ptr[mut usize]](header)^ = class
        start :: cast[mut rawptr](cast[usize](header) + 16)
        intrinsics.mem_zero(start, size)
        return start
    }

    heap_free #no_context :: fn(memory: rawptr) {
        header :: cast[usize](memory) - 16
        first :: cast[ptr[usize]](cast[rawptr](header))^
        if first >= PAGE_HEAP_CLASSES {
            // Pages of its own: how many bytes of them, then where they start
            unmap_pages(cast[rawptr](cast[ptr[usize]](cast[rawptr](header + 8))^), first)
            return void
        }
        heap :: &intrinsics.process_state().heap
        heap_lock(heap)
        cast[ptr[mut rawptr]](cast[rawptr](header))^ = heap.free_lists[first]
        heap.free_lists[first] = cast[rawptr](header)
        heap_unlock(heap)
    }
}

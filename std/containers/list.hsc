package containers

/*
 * An intrusive doubly linked list: each value has a ListLink in it, and the list links those, so
 * adding and removing never allocates. A value can be in as many lists as it has links.
 *
 *     Task :: struct {
 *         queue_link : ListLink,
 *         id : u32,
 *     }
 *     ready : List
 *     list_push_back(&ready, &task.queue_link)
 *     first :: list_pop_front(&ready) or_return void
 *     task :: entry_of[Task](first, offset_of(Task, queue_link))
 *
 * Linked values have to outlive their place in the list, so they can't be on a stack.
 */
ListLink :: struct {
    next : ptr[mut ListLink]?,
    previous : ptr[mut ListLink]?,
}

List :: struct {
    first : ptr[mut ListLink]?,
    last : ptr[mut ListLink]?,
    count : usize,
}

list_push_back :: fn(list: ptr[mut List], link #escaping : ptr[mut ListLink]) {
    link.next = null
    link.previous = list.last
    match list.last {
        case Some(last) => last.next = link
        case None => list.first = link
    }
    list.last = link
    list.count += 1
}

list_push_front :: fn(list: ptr[mut List], link #escaping : ptr[mut ListLink]) {
    link.previous = null
    link.next = list.first
    match list.first {
        case Some(first) => first.previous = link
        case None => list.last = link
    }
    list.first = link
    list.count += 1
}

// Take a link out of the list it's in, which has to be this one.
list_remove :: fn(list: ptr[mut List], link: ptr[mut ListLink]) {
    match link.previous {
        case Some(previous) => previous.next = link.next
        case None => list.first = link.next
    }
    match link.next {
        case Some(next) => next.previous = link.previous
        case None => list.last = link.previous
    }
    link.next = null
    link.previous = null
    if list.count > 0 {
        list.count -= 1
    }
}

list_pop_front :: fn(list: ptr[mut List]) -> ptr[mut ListLink]? {
    first :: list.first or_return null
    list_remove(list, first)
    return first
}

// The value a link is in, given where the link is in it: offset_of(T, the link's field).
entry_of :: fn[T](link: ptr[mut ListLink], offset: usize) -> ptr[mut T] {
    return cast[ptr[mut T]](cast[rawptr](cast[usize](link) - offset))
}

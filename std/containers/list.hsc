package containers

/**
 * A link in an intrusive doubly linked list: each value has a ListLink in it, and the list links those, so adding and
 * removing never allocates. A value can be in as many lists as it has links.
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
 * Linked values have to outlive their place in the list, so they can't be on a stack. Nothing in it is atomic, so
 * threads sharing a list need a lock.
 */
ListLink :: struct {
    /** The next link in its list, or null for the last, or one in no list. */
    next : ptr[mut ListLink]?,
    /** The link before it in its list, or null for the first, or one in no list. */
    previous : ptr[mut ListLink]?,
}

/** An intrusive doubly linked list of ListLinks. Its zero value is empty. */
List :: struct {
    /** The first link, or null when the list is empty. */
    first : ptr[mut ListLink]?,
    /** The last link, or null when the list is empty. */
    last : ptr[mut ListLink]?,
    /** How many links are in the list. */
    count : usize,
}

/**
 * Add a link at the back of a list.
 *
 * @param list The list.
 * @param link The link, which must not be in a list already; it stays in this one until removed, so its value has to
 *     outlive its place in it.
 */
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

/**
 * Add a link at the front of a list.
 *
 * @param list The list.
 * @param link The link, which must not be in a list already; it stays in this one until removed, so its value has to
 *     outlive its place in it.
 */
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

/**
 * Take a link out of the list it's in.
 *
 * @param list The list, which has to be the one the link is in: nothing checks it, and another list is left broken.
 * @param link The link, unlinked afterwards (its next and previous null), so it can go in a list again.
 */
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

/**
 * Take the first link out of a list.
 *
 * @param list The list.
 * @return The first link, unlinked; null if the list is empty.
 */
list_pop_front :: fn(list: ptr[mut List]) -> ptr[mut ListLink]? {
    first :: list.first or_return null
    list_remove(list, first)
    return first
}

/**
 * Find the value a link is in.
 *
 * @tparam T The value's type.
 * @param link The link, which has to be in a T at offset: nothing checks it.
 * @param offset Where the link is in the value, in bytes: offset_of(T, the link's field).
 * @return The value, at offset bytes before the link.
 */
entry_of :: fn[T](link: ptr[mut ListLink], offset: usize) -> ptr[mut T] {
    return cast[ptr[mut T]](cast[rawptr](cast[usize](link) - offset))
}

package ui

import runtime from "base"

/*
 * The tree read from outside: selectors, for tests to find widgets and drive them, and the accessibility export, the
 * same tree as a reader of the screen is given. Both read the last frame's tree, after end and before the next begin.
 *
 * A selector is steps separated by "/" (a child) or "//" (a descendant at any depth), from the root, each step a
 * name ("Save"), a role ("role=button"), or text ("text=Save", the same as a name). "//text=Close" is any node named
 * Close; "settings//role=checkbox" any check box under a node named settings.
 */

/** A node as a reader of the screen is given it. */
Accessible :: struct {
    /** Its ID. */
    id : ID,
    /** Its parent's ID; 0 for the root. */
    parent : ID,
    /** What it is. */
    role : Role,
    /** Its name: where it starts in the UI's text, and how many bytes. */
    name_start : u32,
    /** How many bytes of name it has. */
    name_count : u32,
    /** Its left edge, in pixels. */
    x : f32,
    /** Its top edge. */
    y : f32,
    /** Its width. */
    w : f32,
    /** Its height. */
    h : f32,
    /** Whether it has focus. */
    focused : bool,
    /** For a check box, whether it's checked. */
    checked : bool,
}

/**
 * Give the last frame's tree as a reader of the screen is given it, every node in order, parents before children.
 *
 * @param ui The UI, after end.
 * @param into Where the nodes go, its contents replaced.
 */
accessible :: fn(ui: ptr[mut Ui], into: ptr[mut Accessible[..]]) {
    runtime.array_reset(into)
    for each in ui.nodes {
        parent :: if each.parent == NO_NODE { cast[u64](0) } else { node(ui, each.parent).id }
        runtime.array_add(into, Accessible.{id = each.id, parent = parent, role = each.box.role, name_start = each.name_start,
            name_count = each.name_count, x = each.x, y = each.y, w = each.w, h = each.h, focused = each.id == ui.focus && each.id != 0,
            checked = each.checked})
    }
}

/** A node's name, as the frame's text holds it. */
name_of :: fn(ui: ptr[Ui], start: u32, count: u32) -> u8[] {
    return text_of(ui.text[0..<ui.text.count], start, count)
}

/** A role's name in a selector. */
role_name :: fn(role: Role) -> string {
    return match role {
        case .Group => "group"
        case .Text => "text"
        case .Button => "button"
        case .CheckBox => "checkbox"
        case .TextField => "textfield"
        case .List => "list"
        case .ListItem => "listitem"
        case .ScrollArea => "scrollarea"
    }
}

/** Whether bytes are a string's. */
equal :: fn(bytes: u8[], text: string) -> bool {
    other :: string_bytes(text)
    if bytes.count != other.count {
        return false
    }
    for byte, i in bytes {
        if i < other.count && other[i] != byte {
            return false
        }
    }
    return true
}

/** Whether a node matches a selector's step. */
matches :: fn(ui: ptr[mut Ui], index: u32, step: string) -> bool {
    made :: node(ui, index)
    bytes :: string_bytes(step)
    if bytes.count > 5 && equal(bytes[0..<5], "role=") {
        return equal(bytes[5..<bytes.count], role_name(made.box.role))
    }
    wanted :: if bytes.count > 5 && equal(bytes[0..<5], "text=") { bytes[5..<bytes.count] } else { bytes }
    name :: name_of(ui, made.name_start, made.name_count)
    if name.count != wanted.count {
        return false
    }
    for byte, i in name {
        if i < wanted.count && wanted[i] != byte {
            return false
        }
    }
    return true
}

/**
 * Find the first node a selector matches, in the tree's order.
 *
 * @param ui The UI, after end.
 * @param selector Steps separated by "/" or "//", from the root, as the package's comment says.
 * @return Its ID; null when nothing matches, or the selector's empty.
 */
find :: fn(ui: ptr[mut Ui], selector: string) -> ID? {
    bytes :: string_bytes(selector)
    if bytes.count == 0 || ui.nodes.count == 0 {
        return null
    }
    found :: find_from(ui, 0, bytes, 0)
    return if found == NO_NODE { cast[ID?](null) } else { node(ui, found).id }
}

/**
 * Find, under a node, the first that matches a selector's rest, from a place in it.
 *
 * @param ui The UI.
 * @param under The node whose children, or descendants for "//", the next step is tried on.
 * @param selector The whole selector.
 * @param at Where the rest starts in it: at a "/" or "//", or at a step for the selector's first.
 * @return The node; NO_NODE for none.
 */
find_from :: fn(ui: ptr[mut Ui], under: u32, selector: u8[], at: usize) -> u32 {
    start := at
    deep := at == 0
    if start < selector.count && selector[start] == cast[u8]('/') {
        start += 1
        deep = false
        if start < selector.count && selector[start] == cast[u8]('/') {
            start += 1
            deep = true
        }
    }
    end := start
    for i in start..<selector.count {
        if selector[i] == cast[u8]('/') {
            break
        }
        end = i + 1
    }
    if end <= start || end > selector.count {
        return NO_NODE
    }
    step :: string_of(&selector[start], end - start)
    return search(ui, under, step, deep, selector, end, 0)
}

/** Try a step on a node's children, or descendants when deep, and the selector's rest under what matches. */
search :: fn(ui: ptr[mut Ui], under: u32, step: string, deep: bool, selector: u8[], rest: usize, depth: usize) -> u32 {
    if depth >= MAX_DEPTH {
        return NO_NODE
    }
    child := node(ui, under).first
    for walked in cast[usize](0)..<MAX_NODES {
        if child == NO_NODE {
            break
        }
        if matches(ui, child, step) {
            found :: if rest >= selector.count { child } else { find_from(ui, child, selector, rest) }
            if found != NO_NODE {
                return found
            }
        }
        if deep {
            found :: search(ui, child, step, true, selector, rest, depth + 1)
            if found != NO_NODE {
                return found
            }
        }
        child = node(ui, child).next
    }
    return NO_NODE
}

/** A point on the frame, in pixels from its top left. */
Spot :: struct {
    /** Across. */
    x : f32,
    /** Down. */
    y : f32,
}

/** Where a widget is: its middle, for a test's pointer; null for an ID the last frame didn't lay out. */
middle_of :: fn(ui: ptr[Ui], id: ID) -> Spot? {
    place :: kept_of(ui, id)
    if place.id == 0 {
        return null
    }
    return Spot.{x = place.x + place.w / 2, y = place.y + place.h / 2}
}

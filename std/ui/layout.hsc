package ui

import runtime from "base"
import fonts from "std"

/*
 * Layout, as Clay does it, one axis at a time, widths first: each box's content width found bottom-up (what it wants,
 * and the least it can take); widths given top-down, growing boxes sharing what's left by weight and boxes that don't
 * fit shrinking towards their least; text wrapped to its width; then heights the same way, bottom-up and top-down; then
 * positions, top-down, with alignment, gaps, padding and scrolling.
 *
 * Nodes are made before their children, so going through them backwards is bottom-up, and forwards top-down.
 */

/** The most lines one text has; past them, the rest isn't laid out. */
MAX_LINES :: 4096

/** The faces a frame's text is in, opened once for its layout and drawing. */
Faces :: struct #scoped {
    /** The proportional face. */
    sans : fonts.Font,
    /** The monospaced face. */
    mono : fonts.Font,
}

/** Open a UI's faces; a face that doesn't open is empty, its text measured as nothing. */
faces_of :: fn(ui: ptr[Ui]) -> Faces {
    return Faces.{sans = fonts.open(ui.sans) or_else fonts.Font.{}, mono = fonts.open(ui.mono) or_else fonts.Font.{}}
}

/** The face a style's in. */
face :: fn(faces: ptr[Faces], style: TextStyle) -> ptr[fonts.Font] {
    return if style.mono { &faces.mono } else { &faces.sans }
}

/** Lay out the frame's tree: every node's place and size. */
lay_out :: fn(ui: ptr[mut Ui]) {
    faces :: faces_of(ui)
    count :: cast[u32](ui.nodes.count)
    lines : fonts.Line[..]
    defer runtime.array_free(&lines)
    // Widths: what each wants, bottom-up; then given, top-down
    for step in cast[u32](0)..<count {
        fit_width(ui, &faces, count - 1 - step, &lines)
    }
    for index in cast[u32](0)..<count {
        give_widths(ui, index)
    }
    // Heights, with text wrapped to its width
    for step in cast[u32](0)..<count {
        fit_height(ui, &faces, count - 1 - step, &lines)
    }
    for index in cast[u32](0)..<count {
        give_heights(ui, index)
    }
    root :: node(ui, 0)
    root.x = 0
    root.y = 0
    for index in cast[u32](0)..<count {
        place_children(ui, index)
    }
}

/** A size kept within an axis's least and most (0 for no most). */
clamp_axis :: fn(size: f32, axis: Axis) -> f32 {
    low :: if size < axis.min { axis.min } else { size }
    return if axis.max > 0 && low > axis.max { axis.max } else { low }
}

/** Find what a node wants across, and the least it can take: from its text, or its children's. */
fit_width :: fn(ui: ptr[mut Ui], faces: ptr[Faces], index: u32, lines: ptr[mut fonts.Line[..]]) {
    made :: node(ui, index)
    want := cast[f32](0)
    least := cast[f32](0)
    if made.is_text {
        style :: resolved(ui, made.style)
        font :: face(faces, style)
        text :: text_of(ui.text[0..<ui.text.count], made.text_start, made.text_count)
        // Unwrapped, each line as long as it is; wrapped, its longest word
        runtime.array_reset(lines)
        fonts.wrap(font, style.size, text, 1.0e9, lines)
        for line in lines^ {
            want = if line.width > want { line.width } else { want }
        }
        least = if style.wrap { longest_word(font, style.size, text) } else { want }
    }
    else {
        row :: made.box.direction == .Row
        children := cast[f32](0)
        child := made.first
        for step in cast[usize](0)..<MAX_NODES {
            if child == NO_NODE {
                break
            }
            each :: node(ui, child)
            if row {
                want += each.fit_w
                least += each.min_w
            }
            else {
                want = if each.fit_w > want { each.fit_w } else { want }
                least = if each.min_w > least { each.min_w } else { least }
            }
            children += 1
            child = each.next
        }
        if row && children > 1 {
            want += made.box.gap * (children - 1)
            least += made.box.gap * (children - 1)
        }
        want += 2 * made.box.padding_x
        least += 2 * made.box.padding_x
    }
    axis :: made.box.width
    match axis.kind {
        case .Fixed => {
            made.fit_w = axis.value
            made.min_w = axis.value
        }
        case .Percent => {
            made.fit_w = 0
            made.min_w = 0
        }
        case _ => {
            made.fit_w = clamp_axis(want, axis)
            made.min_w = clamp_axis(least, axis)
        }
    }
}

/** The widest word of text, at a size: the narrowest its wrapping can make it. */
longest_word :: fn(font: ptr[fonts.Font], size: f32, text: u8[]) -> f32 {
    longest := cast[f32](0)
    start := cast[usize](0)
    for i in cast[usize](0)..<text.count + 1 {
        at_end :: i >= text.count
        breaks :: at_end || text[i % text.count] == cast[u8](' ') || text[i % text.count] == cast[u8]('\n')
        if breaks {
            if i > start && i <= text.count {
                width :: fonts.measure(font, size, text[start..<i])
                longest = if width > longest { width } else { longest }
            }
            start = i + 1
        }
    }
    return longest
}

/** Give a node's children their widths, from its own. */
give_widths :: fn(ui: ptr[mut Ui], index: u32) {
    parent :: node(ui, index)
    if index == 0 {
        parent.w = parent.fit_w
    }
    inner :: max_of(parent.w - 2 * parent.box.padding_x, 0)
    if parent.box.direction == .Column {
        child := parent.first
        for step in cast[usize](0)..<MAX_NODES {
            if child == NO_NODE {
                break
            }
            each :: node(ui, child)
            each.w = across(each, each.box.width, each.fit_w, each.min_w, inner)
            child = each.next
        }
        return void
    }
    share(ui, parent, inner, true)
}

/** A child's size across its parent: what its axis says, within what the parent has. */
across :: fn(each: ptr[Node], axis: Axis, fit: f32, least: f32, inner: f32) -> f32 {
    return match axis.kind {
        case .Fixed => axis.value
        case .Percent => clamp_axis(inner * axis.value / 100, axis)
        case .Grow => clamp_axis(inner, axis)
        case .Fit => if fit <= inner { fit } else { max_of(least, inner) }
    }
}

/** The larger of two sizes. */
max_of :: fn(a: f32, b: f32) -> f32 {
    return if a > b { a } else { b }
}

/**
 * Share a box's room along its direction among its children: fixed and percent sizes first, then each the size it
 * fits; what's left grown into by weight, in rounds, each round giving all of it or pinning a child at its most; or,
 * with too little, children shrunk towards their least, the widest first.
 *
 * @param ui The UI.
 * @param parent The box.
 * @param inner Its room along its direction, its padding taken off.
 * @param widths Whether it's widths shared, across a row, or heights, down a column.
 */
share :: fn(ui: ptr[mut Ui], parent: ptr[Node], inner: f32, widths: bool) {
    children := cast[f32](0)
    used := cast[f32](0)
    weight := cast[f32](0)
    child := parent.first
    for step in cast[usize](0)..<MAX_NODES {
        if child == NO_NODE {
            break
        }
        each :: node(ui, child)
        axis :: if widths { each.box.width } else { each.box.height }
        fit :: if widths { each.fit_w } else { each.fit_h }
        size :: match axis.kind {
            case .Fixed => axis.value
            case .Percent => clamp_axis(inner * axis.value / 100, axis)
            case _ => fit
        }
        set_size(each, widths, size)
        used += size
        if axis.kind == .Grow {
            weight += if axis.value > 0 { axis.value } else { cast[f32](1) }
        }
        children += 1
        child = each.next
    }
    room := inner - used - (if children > 1 { parent.box.gap * (children - 1) } else { cast[f32](0) })
    // Grown into, in rounds: a child at its most leaves the rest to the others
    for round in cast[usize](0)..<16 {
        if room <= 0.01 || weight <= 0 {
            break
        }
        given := cast[f32](0)
        pinned := cast[f32](0)
        child = parent.first
        for step in cast[usize](0)..<MAX_NODES {
            if child == NO_NODE {
                break
            }
            each :: node(ui, child)
            axis :: if widths { each.box.width } else { each.box.height }
            if axis.kind == .Grow {
                part :: if axis.value > 0 { axis.value } else { cast[f32](1) }
                before :: size_of_node(each, widths)
                wanted :: before + room * part / weight
                after :: if axis.max > 0 && wanted > axis.max { axis.max } else { wanted }
                if axis.max > 0 && wanted >= axis.max && before < axis.max {
                    pinned += part
                }
                if before < after {
                    set_size(each, widths, after)
                    given += after - before
                }
            }
            child = each.next
        }
        room -= given
        weight -= pinned
        if given <= 0.01 {
            break
        }
    }
    // Shrunk, widest first, towards each child's least
    for round in cast[usize](0)..<64 {
        if room >= -0.01 {
            break
        }
        widest := NO_NODE
        widest_size := cast[f32](0)
        child = parent.first
        for step in cast[usize](0)..<MAX_NODES {
            if child == NO_NODE {
                break
            }
            each :: node(ui, child)
            axis :: if widths { each.box.width } else { each.box.height }
            least :: if widths { each.min_w } else { cast[f32](0) }
            size :: size_of_node(each, widths)
            if axis.kind != .Fixed && size > least + 0.01 && size > widest_size {
                widest = child
                widest_size = size
            }
            child = each.next
        }
        if widest == NO_NODE {
            break
        }
        each :: node(ui, widest)
        least :: if widths { each.min_w } else { cast[f32](0) }
        cut :: if widest_size - least < -room { widest_size - least } else { -room }
        set_size(each, widths, widest_size - cut)
        room += cut
    }
}

/** A node's width or height. */
size_of_node :: fn(each: ptr[Node], widths: bool) -> f32 {
    return if widths { each.w } else { each.h }
}

/** Set a node's width or height. */
set_size :: fn(each: ptr[mut Node], widths: bool, size: f32) {
    if widths {
        each.w = size
    }
    else {
        each.h = size
    }
}

/** Find what a node wants down, its text wrapped to its width or its children's heights. */
fit_height :: fn(ui: ptr[mut Ui], faces: ptr[Faces], index: u32, lines: ptr[mut fonts.Line[..]]) {
    made :: node(ui, index)
    want := cast[f32](0)
    if made.is_text {
        style :: resolved(ui, made.style)
        font :: face(faces, style)
        text :: text_of(ui.text[0..<ui.text.count], made.text_start, made.text_count)
        runtime.array_reset(lines)
        fonts.wrap(font, style.size, text, if style.wrap { made.w + 0.5 } else { cast[f32](1.0e9) }, lines)
        count :: if lines.count > 0 { lines.count } else { cast[usize](1) }
        height :: if font.units_per_em == 0 { style.size * 1.4 } else { fonts.line_height(font, style.size) }
        want = cast[f32](count) * height
    }
    else {
        column :: made.box.direction == .Column
        children := cast[f32](0)
        child := made.first
        for step in cast[usize](0)..<MAX_NODES {
            if child == NO_NODE {
                break
            }
            each :: node(ui, child)
            if column {
                want += each.fit_h
            }
            else {
                want = if each.fit_h > want { each.fit_h } else { want }
            }
            children += 1
            child = each.next
        }
        if column && children > 1 {
            want += made.box.gap * (children - 1)
        }
        want += 2 * made.box.padding_y
    }
    made.content_h = want
    axis :: made.box.height
    made.fit_h = if axis.kind == .Fixed { axis.value } else if axis.kind == .Percent { cast[f32](0) } else { clamp_axis(want, axis) }
    // A scroll area fits no more than it's given; its content scrolls
    if made.scrolls && axis.kind != .Fixed {
        made.fit_h = clamp_axis(0, axis)
    }
}

/** Give a node's children their heights, from its own. */
give_heights :: fn(ui: ptr[mut Ui], index: u32) {
    parent :: node(ui, index)
    if index == 0 {
        parent.h = parent.fit_h
    }
    inner :: max_of(parent.h - 2 * parent.box.padding_y, 0)
    if parent.box.direction == .Row {
        child := parent.first
        for step in cast[usize](0)..<MAX_NODES {
            if child == NO_NODE {
                break
            }
            each :: node(ui, child)
            each.h = across(each, each.box.height, each.fit_h, each.fit_h, inner)
            child = each.next
        }
        return void
    }
    // A scroll area's children aren't squeezed into it: they're as tall as they fit
    if parent.scrolls {
        child := parent.first
        for step in cast[usize](0)..<MAX_NODES {
            if child == NO_NODE {
                break
            }
            each :: node(ui, child)
            each.h = if each.box.height.kind == .Fixed { each.box.height.value } else { each.fit_h }
            child = each.next
        }
        return void
    }
    share(ui, parent, inner, false)
}

/** Place a node's children inside it: along its direction with gaps, aligned, scrolled by its kept scroll. */
place_children :: fn(ui: ptr[mut Ui], index: u32) {
    parent :: node(ui, index)
    row :: parent.box.direction == .Row
    inner_w :: max_of(parent.w - 2 * parent.box.padding_x, 0)
    inner_h :: max_of(parent.h - 2 * parent.box.padding_y, 0)
    used := cast[f32](0)
    children := cast[f32](0)
    child := parent.first
    for step in cast[usize](0)..<MAX_NODES {
        if child == NO_NODE {
            break
        }
        each :: node(ui, child)
        used += if row { each.w } else { each.h }
        children += 1
        child = each.next
    }
    if children > 1 {
        used += parent.box.gap * (children - 1)
    }
    if parent.scrolls {
        parent.content_h = used + 2 * parent.box.padding_y
    }
    room :: (if row { inner_w } else { inner_h }) - used
    main_align :: if row { parent.box.align_x } else { parent.box.align_y }
    offset := match main_align {
        case .Start => cast[f32](0)
        case .Center => max_of(room, 0) / 2
        case .End => max_of(room, 0)
    }
    scroll :: if parent.scrolls { kept_of(ui, parent.id).scroll } else { cast[f32](0) }
    child = parent.first
    for step in cast[usize](0)..<MAX_NODES {
        if child == NO_NODE {
            break
        }
        each :: node(ui, child)
        if row {
            each.x = parent.x + parent.box.padding_x + offset
            each.y = parent.y + parent.box.padding_y + aligned(parent.box.align_y, inner_h - each.h)
            offset += each.w + parent.box.gap
        }
        else {
            each.x = parent.x + parent.box.padding_x + aligned(parent.box.align_x, inner_w - each.w)
            each.y = parent.y + parent.box.padding_y + offset - scroll
            offset += each.h + parent.box.gap
        }
        child = each.next
    }
}

/** How far into room something's put by an alignment. */
aligned :: fn(align: Align, room: f32) -> f32 {
    return match align {
        case .Start => cast[f32](0)
        case .Center => max_of(room, 0) / 2
        case .End => max_of(room, 0)
    }
}

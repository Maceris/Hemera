/*
 * == and != on fixed arrays, structs and tagged unions (docs/types.md, Equality): element by element, member by member,
 * and by variant and its values.
 */
package equality

import testing from "std"

/** A fixed array compared as a whole. */
Guid :: u8[16]

/** A struct with no padding. */
Point :: struct {
    /** Across; any value. */
    x : f64,
    /** Down; any value. */
    y : f64,
}

/** A byte, then padding, then a u64: the padding isn't compared. */
Padded :: struct {
    /** Before the padding. */
    small : u8,
    /** After it. */
    large : u64,
    /** Followed by padding at the end. */
    last : u16,
}

/** A tagged union whose variants hold nothing, one value, or two. */
Shape :: union {
    /** A circle of a radius. */
    Circle(f64),
    /** A rectangle between two corners. */
    Rectangle(Point, Point),
    /** No shape. */
    Nothing,
}

/**
 * Make a GUID of one repeated byte.
 *
 * @param byte Every byte's value.
 * @return The GUID.
 */
guid :: fn(byte: u8) -> Guid {
    made : Guid
    for &each in made {
        each^ = byte
    }
    return made
}

/**
 * Make a Padded with junk in its padding, which == doesn't look at.
 *
 * @param small The small member.
 * @param large The large member.
 * @param last The last member.
 * @param junk What every padding byte is.
 * @return The Padded.
 */
padded :: fn(small: u8, large: u64, last: u16, junk: u8) -> Padded {
    made : Padded
    bytes :: cast[ptr[mut u8]](&made)
    for i in 0..<size_of(Padded) {
        cast[ptr[mut u8]](cast[u64](bytes) + cast[u64](i))^ = junk
    }
    made.small = small
    made.large = large
    made.last = last
    return made
}

compares_fixed_arrays_element_by_element #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, guid(1) == guid(1), "the same sixteen bytes")
    testing.expect(t, guid(1) != guid(2), "every byte differs")
    a := guid(3)
    a[15] = 4
    testing.expect(t, a != guid(3), "only the last byte differs, and it's compared too")
    return .Ok
}

compares_structs_member_by_member #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    one :: Point.{1, 2}
    also_one :: Point.{1, 2}
    two :: Point.{2, 1}
    testing.expect(t, one == also_one, "the same members")
    testing.expect(t, one != two, "the same values, in other members")
    points :: Point.[Point.{1, 2}, Point.{3, 4}]
    others :: Point.[Point.{1, 2}, Point.{3, 5}]
    testing.expect(t, points == points, "an array of structs is equal to itself")
    testing.expect(t, points != others, "one member of the second element differs")
    // A typed literal on the left of an operator
    testing.expect(t, Point.{1, 2} == one, "a literal on the left compares as a value would")
    testing.expect(t, Point.{1, 2} != Point.{2, 1}, "two literals, their members swapped")
    return .Ok
}

leaves_padding_out #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, padded(1, 2, 3, 0) == padded(1, 2, 3, 0xff), "only the padding differs")
    testing.expect(t, padded(1, 2, 3, 0) != padded(1, 2, 4, 0), "the member before the end padding is compared")
    return .Ok
}

compares_unions_by_variant_and_values #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    circle : Shape = .Circle(1.5)
    same : Shape = .Circle(1.5)
    bigger : Shape = .Circle(2.5)
    box : Shape = .Rectangle(Point.{0, 0}, Point.{1, 1})
    nothing : Shape = .Nothing
    testing.expect(t, circle == same, "the same variant and value")
    testing.expect(t, circle != bigger, "the same variant, another value")
    testing.expect(t, circle != box, "another variant")
    testing.expect(t, box == box, "a variant of two values is equal to itself")
    testing.expect(t, nothing == nothing, "a variant holding nothing is equal to itself")
    testing.expect(t, nothing != circle, "a variant holding nothing differs from one holding a value")
    return .Ok
}

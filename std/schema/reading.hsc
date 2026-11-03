package schema

import runtime from "base"

/*
 * Schemas read back (the bytes are schema.hsc's): each type one describes, with what its kind has, for code that meets
 * types only as it runs, like a shell calling programs through their manifests, the schemas of their entries' types.
 * The first type is the one the schema's of; types refer to each other by their places among them, NOWHERE for none.
 * A schema's types can be written as the schema of any one of them (write_rooted), which hashes as schema.hash hashes
 * that type (hash_rooted), so a value of it can be written for a reader that checks its hash.
 */

// A schema read: its own copy of the bytes, and its types in their order. free gives them back.
Schema :: struct {
    bytes : u8[..],
    types : Type[..],
}

Type :: struct {
    kind : Kind,
    size : u64,
    // A struct's, union's, enum's or distinct alias's name
    name : string,
    // An alias's type, an array's or a vector's elements', a pointer's (NOWHERE for a rawptr) or an enum's backing type
    base : usize,
    // An integer's and a float's: 0 native, 1 little, 2 big
    endianness : u8,
    is_signed : bool,
    is_raw : bool,
    is_mutable : bool,
    is_relative : bool,
    is_packed : bool,
    is_union : bool,
    is_bits : bool,
    null_is_none : bool,
    never_returns : bool,
    // A struct's alignment, a vector's count
    count : u64,
    // A union's tag type, NOWHERE for none
    tag : usize,
    members : Member[..],
    inputs : Input[..],
    outputs : usize[..],
    constants : Constant[..],
    variants : Variant[..],
    dimensions : Dimension[..],
    // Where its description is among the bytes, and where in it each place it refers to is written, in order
    at : usize,
    end : usize,
    references : usize[..],
}

Member :: struct {
    name : string,
    type : usize,
    offset : u64,
    is_using : bool,
}

// A function's parameter.
Input :: struct {
    name : string,
    type : usize,
    is_varargs : bool,
    is_escaping : bool,
}

// An enum's member: its value's low and high 64 bits.
Constant :: struct {
    name : string,
    value : u64,
    high : u64,
}

Variant :: struct {
    name : string,
    held : Held[..],
}

// What a union's variant holds: its type, and where it is in the union.
Held :: struct {
    type : usize,
    offset : u64,
}

DimensionKind :: enum #backed_by(u8) {
    Static = 1,
    Dynamic = 2,
    View = 3,
}

Dimension :: struct {
    kind : DimensionKind,
    count : u64,
    is_mutable : bool,
}

// The most types a schema read has.
MAX_TYPES : usize : 65536

/*
 * bytes read as a schema: null if they aren't one, of this version, every place in them one of its types, and nothing
 * after its last.
 */
parse :: fn(bytes: u8[]) -> Schema? {
    schema := Schema.{}
    for byte in bytes {
        runtime.array_add(&schema.bytes, byte)
    }
    if !read_types(&schema) {
        free(&schema)
        return null
    }
    return schema
}

// What a schema read holds, given back.
free :: fn(schema: ptr[mut Schema]) {
    for &type in schema.types {
        runtime.array_free(&type.members)
        runtime.array_free(&type.inputs)
        runtime.array_free(&type.outputs)
        runtime.array_free(&type.constants)
        for &variant in type.variants {
            runtime.array_free(&variant.held)
        }
        runtime.array_free(&type.variants)
        runtime.array_free(&type.dimensions)
        runtime.array_free(&type.references)
    }
    runtime.array_free(&schema.types)
    runtime.array_free(&schema.bytes)
}

// The type at a place, or null.
type_in :: fn(schema: ptr[Schema], place: usize) -> ptr[Type]? {
    if place >= schema.types.count {
        return null
    }
    return &schema.types[place]
}

// The place of the type at a place, through its aliases, distinct ones too: NOWHERE for none.
unaliased_place :: fn(schema: ptr[Schema], place: usize) -> usize {
    at := place
    for step in 0..<ALIAS_LIMIT {
        type :: type_in(schema, at) or_return NOWHERE
        if type.kind != .Alias {
            return at
        }
        at = type.base
    }
    return NOWHERE
}

/*
 * The schema of the type at a place among a schema's, written to the end of into, as schema.write writes it for that
 * type: the types it reaches, numbered again from it. Without the memory, the allocator's error, into as it was.
 */
write_rooted :: fn(schema: ptr[Schema], place: usize, into: ptr[mut u8[..]]) -> runtime.AllocatorError? {
    start :: into.count
    if place >= schema.types.count {
        return null
    }
    // The places reached, breadth first, in the order each type refers to them, as schema.write numbers them
    order : usize[..]
    defer runtime.array_free(&order)
    renumbered : usize[..]
    defer runtime.array_free(&renumbered)
    for i in 0..<schema.types.count {
        error :: runtime.array_try_add(&renumbered, NOWHERE)
        if error != null {
            return error
        }
    }
    first_error :: runtime.array_try_add(&order, place)
    if first_error != null {
        return first_error
    }
    if place < renumbered.count {
        renumbered[place] = 0
    }
    next : usize = 0
    loop {
        if next >= order.count {
            break
        }
        type :: type_in(schema, order[next]) or_return null
        for reference in type.references {
            referred :: cast[usize](read(schema.bytes, reference, 4))
            if referred < renumbered.count && renumbered[referred] == NOWHERE {
                renumbered[referred] = order.count
                error :: runtime.array_try_add(&order, referred)
                if error != null {
                    return error
                }
            }
        }
        next += 1
    }
    error := add_all(into, u8.[0x48, 0x53, 0x43, 0x48])
    if error == null {
        error = add_number(into, cast[u64](VERSION), 2)
    }
    if error == null {
        error = add_number(into, cast[u64](order.count), 4)
    }
    for each in order {
        type :: type_in(schema, each) or_return null
        // Its description, each place it refers to written as it's numbered now
        reference_index : usize = 0
        at := type.at
        loop {
            if at >= type.end || error != null {
                break
            }
            if reference_index < type.references.count && type.references[reference_index] == at {
                referred :: cast[usize](read(schema.bytes, at, 4))
                renumber :: if referred < renumbered.count { renumbered[referred] } else { cast[usize](0) }
                error = add_number(into, cast[u64](renumber), 4)
                reference_index += 1
                at += 4
                continue
            }
            error = runtime.array_try_add(into, byte_at(schema.bytes, at))
            at += 1
        }
    }
    if error != null {
        runtime.resizable(into).count = start
    }
    return error
}

// The schema hash of the type at a place among a schema's, as schema.hash gives it for that type.
hash_rooted :: fn(schema: ptr[Schema], place: usize) -> u8[32] {
    bytes : u8[..]
    defer runtime.array_free(&bytes)
    if write_rooted(schema, place, &bytes) != null {
        nothing : u8[32]
        return nothing
    }
    return runtime.hash_blake3(bytes)
}

add_all :: fn(into: ptr[mut u8[..]], bytes: u8[]) -> runtime.AllocatorError? {
    for byte in bytes {
        error :: runtime.array_try_add(into, byte)
        if error != null {
            return error
        }
    }
    return null
}

add_number :: fn(into: ptr[mut u8[..]], value: u64, count: usize) -> runtime.AllocatorError? {
    for i in cast[usize](0)..<count {
        error :: runtime.array_try_add(into, cast[u8]((value >> (8 * cast[u64](i))) & 0xff))
        if error != null {
            return error
        }
    }
    return null
}

// The types of a schema's bytes, each read in turn: whether they're all there, and nothing after them.
read_types :: fn(schema: ptr[mut Schema]) -> bool {
    bytes :: schema.bytes
    if first_type(bytes) == NOWHERE {
        return false
    }
    count :: cast[usize](read(bytes, 6, 4))
    if count == 0 || count > MAX_TYPES {
        return false
    }
    at := cast[usize](10)
    for i in cast[usize](0)..<count {
        made := Type.{base = NOWHERE, tag = NOWHERE, at = at}
        at = read_type(schema, &made, at, count)
        made.end = at
        runtime.array_add(&schema.types, made)
        if at == NOWHERE {
            return false
        }
    }
    return at == bytes.count
}

/*
 * The type described at `at`, into made: where its description ends, NOWHERE if it's cut short, of a kind there isn't,
 * or refers to a place past count.
 */
read_type :: fn(schema: ptr[mut Schema], made: ptr[mut Type], start: usize, count: usize) -> usize {
    bytes :: schema.bytes
    if !fits(bytes, start, 9) {
        return NOWHERE
    }
    kind :: byte_at(bytes, start)
    if kind < cast[u8](Kind.Alias) || kind > cast[u8](Kind.Void) {
        return NOWHERE
    }
    made.kind = cast[Kind](kind)
    made.size = read(bytes, start + 1, 8)
    at := start + 9
    if made.kind == .Alias {
        made.name = name_at(schema, &at)
        made.base = reference_at(schema, made, &at, count)
    }
    else if made.kind == .Array {
        made.base = reference_at(schema, made, &at, count)
        dimensions :: number_at(bytes, &at, 4)
        for i in cast[u64](0)..<dimensions {
            if at == NOWHERE {
                break
            }
            dimension_kind :: number_at(bytes, &at, 1)
            dimension_count :: number_at(bytes, &at, 8)
            mutable :: number_at(bytes, &at, 1) != 0
            if dimension_kind < 1 || dimension_kind > 3 {
                return NOWHERE
            }
            runtime.array_add(&made.dimensions, Dimension.{kind = cast[DimensionKind](cast[u8](dimension_kind)), count = dimension_count,
                is_mutable = mutable})
        }
    }
    else if made.kind == .Enum {
        made.name = name_at(schema, &at)
        made.base = reference_at(schema, made, &at, count)
        members :: number_at(bytes, &at, 4)
        for i in cast[u64](0)..<members {
            if at == NOWHERE {
                break
            }
            name :: name_at(schema, &at)
            low :: number_at(bytes, &at, 8)
            high :: number_at(bytes, &at, 8)
            runtime.array_add(&made.constants, Constant.{name = name, value = low, high = high})
        }
    }
    else if made.kind == .Float {
        made.endianness = cast[u8](number_at(bytes, &at, 1))
    }
    else if made.kind == .Function {
        inputs :: number_at(bytes, &at, 4)
        for i in cast[u64](0)..<inputs {
            if at == NOWHERE {
                break
            }
            name :: name_at(schema, &at)
            type :: reference_at(schema, made, &at, count)
            varargs :: number_at(bytes, &at, 1) != 0
            escaping :: number_at(bytes, &at, 1) != 0
            runtime.array_add(&made.inputs, Input.{name = name, type = type, is_varargs = varargs, is_escaping = escaping})
        }
        outputs :: number_at(bytes, &at, 4)
        for i in cast[u64](0)..<outputs {
            if at == NOWHERE {
                break
            }
            runtime.array_add(&made.outputs, reference_at(schema, made, &at, count))
        }
        made.never_returns = number_at(bytes, &at, 1) != 0
    }
    else if made.kind == .Integer {
        made.is_signed = number_at(bytes, &at, 1) != 0
        made.endianness = cast[u8](number_at(bytes, &at, 1))
    }
    else if made.kind == .Pointer {
        if number_at(bytes, &at, 1) != 0 {
            made.base = reference_at(schema, made, &at, count)
        }
        made.is_relative = number_at(bytes, &at, 1) != 0
        made.is_mutable = number_at(bytes, &at, 1) != 0
    }
    else if made.kind == .String {
        made.is_raw = number_at(bytes, &at, 1) != 0
    }
    else if made.kind == .Struct {
        made.name = name_at(schema, &at)
        made.count = number_at(bytes, &at, 8)
        made.is_packed = number_at(bytes, &at, 1) != 0
        made.is_union = number_at(bytes, &at, 1) != 0
        members :: number_at(bytes, &at, 4)
        for i in cast[u64](0)..<members {
            if at == NOWHERE {
                break
            }
            name :: name_at(schema, &at)
            type :: reference_at(schema, made, &at, count)
            offset :: number_at(bytes, &at, 8)
            uses :: number_at(bytes, &at, 1) != 0
            runtime.array_add(&made.members, Member.{name = name, type = type, offset = offset, is_using = uses})
        }
    }
    else if made.kind == .Union {
        made.name = name_at(schema, &at)
        made.null_is_none = number_at(bytes, &at, 1) != 0
        if number_at(bytes, &at, 1) != 0 {
            made.tag = reference_at(schema, made, &at, count)
        }
        variants :: number_at(bytes, &at, 4)
        for i in cast[u64](0)..<variants {
            if at == NOWHERE {
                break
            }
            variant := Variant.{name = name_at(schema, &at)}
            held :: number_at(bytes, &at, 4)
            for j in cast[u64](0)..<held {
                if at == NOWHERE {
                    break
                }
                type :: reference_at(schema, made, &at, count)
                offset :: number_at(bytes, &at, 8)
                runtime.array_add(&variant.held, Held.{type = type, offset = offset})
            }
            runtime.array_add(&made.variants, variant)
        }
    }
    else if made.kind == .Vector {
        made.base = reference_at(schema, made, &at, count)
        made.count = number_at(bytes, &at, 8)
        made.is_bits = number_at(bytes, &at, 1) != 0
    }
    if at != NOWHERE && at > bytes.count {
        return NOWHERE
    }
    return at
}

// count bytes at `at`, little-endian, and `at` moved past them; NOWHERE in `at`, and 0, if they aren't there.
number_at :: fn(bytes: u8[], at: ptr[mut usize], count: usize) -> u64 {
    if at^ == NOWHERE || !fits(bytes, at^, count) {
        at^ = NOWHERE
        return 0
    }
    value :: read(bytes, at^, count)
    at^ += count
    return value
}

// A name at `at`: its count, then its bytes, which it's a view of.
name_at :: fn(schema: ptr[Schema], at: ptr[mut usize]) -> string {
    count :: cast[usize](number_at(schema.bytes, at, 4))
    if at^ == NOWHERE || !fits(schema.bytes, at^, count) {
        at^ = NOWHERE
        return ""
    }
    bytes : u8[] = schema.bytes
    start :: at^
    name :: if count == 0 || start >= bytes.count { "" } else { string_of(&bytes[start], count) }
    at^ += count
    return name
}

// A place at `at`, noted as one of made's references: NOWHERE in `at` if it's past count.
reference_at :: fn(schema: ptr[Schema], made: ptr[mut Type], at: ptr[mut usize], count: usize) -> usize {
    position :: at^
    place :: cast[usize](number_at(schema.bytes, at, 4))
    if at^ == NOWHERE {
        return NOWHERE
    }
    if place >= count {
        at^ = NOWHERE
        return NOWHERE
    }
    runtime.array_add(&made.references, position)
    return place
}

package schema

import runtime from "base"

/*
 * Schemas read back (the bytes are schema.hsc's): each type one describes, with what its kind has, for code that meets
 * types only as it runs, like a shell calling programs through their manifests, the schemas of their entries' types.
 * The first type is the one the schema's of; types refer to each other by their places among them, NOWHERE for none.
 * A schema's types can be written as the schema of any one of them (write_rooted), which hashes as schema.hash hashes
 * that type (hash_rooted), so a value of it can be written for a reader that checks its hash.
 */

/**
 * A schema read: its own copy of the bytes, and its types in their order. free gives them back.
 *
 * Every name in its types is a view of bytes, so it's good until free.
 */
Schema :: struct {
    /** The schema's bytes, copied from what parse was given, on context.allocator. */
    bytes : u8[..],
    /** Each type it describes, in its place: the first is the one the schema is of. */
    types : Type[..],
}

/** One type a schema describes, with what its kind has; what other kinds have is left zero, or NOWHERE for places. */
Type :: struct {
    /** Which kind of type it is, which says which of the rest it has. */
    kind : Kind,
    /** The size of its values in bytes. */
    size : u64,
    /** A struct's, union's, enum's or distinct alias's name, a view of the schema's bytes; empty for other kinds. */
    name : string,
    /**
     * An alias's type, an array's or a vector's elements', a pointer's (NOWHERE for a rawptr) or an enum's backing
     * type, as a place among the schema's types; NOWHERE for other kinds.
     */
    base : usize,
    /** An integer's and a float's byte order: 0 native, 1 little, 2 big. */
    endianness : u8,
    /** Whether an integer is signed. */
    is_signed : bool,
    /** Whether a string is a cstring. */
    is_raw : bool,
    /** Whether a pointer can change what it points to. */
    is_mutable : bool,
    /** Whether a pointer is a relative one. */
    is_relative : bool,
    /** Whether a struct is #packed. */
    is_packed : bool,
    /** Whether a struct is a #union. */
    is_union : bool,
    /** Whether a vector is v128 to v512, without lanes of its own. */
    is_bits : bool,
    /** Whether a union is an optional of a never-null pointer, with no tag. */
    null_is_none : bool,
    /** Whether a function type is #never_returns. */
    never_returns : bool,
    /** A struct's alignment in bytes, a vector's count of lanes; 0 for other kinds. */
    count : u64,
    /** A union's tag type, as a place among the schema's types; NOWHERE for none, or other kinds. */
    tag : usize,
    /** A struct's members, in order. */
    members : Member[..],
    /** A function type's parameters, in order. */
    inputs : Input[..],
    /** A function type's results' types, as places, in order. */
    outputs : usize[..],
    /** An enum's members, in order. */
    constants : Constant[..],
    /** A union's variants, in order. */
    variants : Variant[..],
    /** An array's dimensions, outermost first. */
    dimensions : Dimension[..],
    /** Where its description starts among the schema's bytes. */
    at : usize,
    /** Where its description ends, the next one's start. */
    end : usize,
    /** Where among the bytes each place it refers to is written, in order, for write_rooted to number them again. */
    references : usize[..],
}

/** A struct's member. */
Member :: struct {
    /** Its name, a view of the schema's bytes. */
    name : string,
    /** Its type, as a place among the schema's types. */
    type : usize,
    /** Its offset in bytes from the struct's start. */
    offset : u64,
    /** Whether it's declared with using. */
    is_using : bool,
}

/** A function's parameter. */
Input :: struct {
    /** Its name, a view of the schema's bytes; empty for one without. */
    name : string,
    /** Its type, as a place among the schema's types. */
    type : usize,
    /** Whether it takes the rest of the arguments. */
    is_varargs : bool,
    /** Whether it's #escaping. */
    is_escaping : bool,
}

/** An enum's member: its value's low and high 64 bits. */
Constant :: struct {
    /** Its name, a view of the schema's bytes. */
    name : string,
    /** Its value's low 64 bits. */
    value : u64,
    /** Its value's high 64 bits, for a backing type wider than 64 bits; 0 otherwise. */
    high : u64,
}

/** A union's variant. */
Variant :: struct {
    /** Its name, a view of the schema's bytes. */
    name : string,
    /** What it holds, in order; empty for a variant that holds nothing. */
    held : Held[..],
}

/** What a union's variant holds: its type, and where it is in the union. */
Held :: struct {
    /** Its type, as a place among the schema's types. */
    type : usize,
    /** Its offset in bytes from the union's start, after the tag. */
    offset : u64,
}

/** The kinds of an array's dimension, as the schema's bytes number them. */
DimensionKind :: enum #backed_by(u8) {
    /** A static array, T[n]. */
    Static = 1,
    /** A dynamic array, T[..]. */
    Dynamic = 2,
    /** A view, T[]. */
    View = 3,
}

/** One dimension of an array. */
Dimension :: struct {
    /** Static, dynamic or a view. */
    kind : DimensionKind,
    /** A static array's count of elements; 0 for the others. */
    count : u64,
    /** Whether a view's elements can be changed through it. */
    is_mutable : bool,
}

/** The most types a schema read has; parse refuses one that says it has more. */
MAX_TYPES : usize : 65536

/**
 * Read bytes as a schema, checking them as it goes, so bytes from elsewhere can be given.
 *
 * Without the memory for its copy or its types, calls context.assertion_handler, as array_add does.
 *
 * @param bytes What schema.write wrote, or bytes claiming to be; they're copied, so they needn't outlast the call.
 * @return The schema, which free gives back; null if they aren't one: not "HSCH" and this version, no types or more
 *     than MAX_TYPES, a type of a kind there isn't or cut short, a place that isn't one of its types, or anything
 *     after its last type.
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

/**
 * Give back what a schema read holds, its bytes and every type's lists, so every view into it is gone.
 *
 * @param schema The schema, from parse; nothing read from it can be used after.
 */
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

/**
 * Find the type at a place among a schema's.
 *
 * @param schema A schema from parse, not yet freed; only read.
 * @param place The type's place, from 0, as types refer to each other.
 * @return The type, good until the schema is freed; null for NOWHERE or any place past the last type.
 */
type_in :: fn(schema: ptr[Schema], place: usize) -> ptr[Type]? {
    if place >= schema.types.count {
        return null
    }
    return &schema.types[place]
}

/**
 * Find the type an alias names, through every alias, distinct ones too.
 *
 * @param schema A schema from parse, not yet freed; only read.
 * @param place The place to start from, which may or may not be an alias.
 * @return The place of the first type that isn't an alias: place itself when it isn't one. NOWHERE if place, or an
 *     alias on the way, refers to no type, or the aliases go more than ALIAS_LIMIT deep, as a loop of them would.
 */
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

/**
 * Write the schema of the type at a place among a schema's to the end of an array, as schema.write writes it for that
 * type: the types it reaches, numbered again from it.
 *
 * Lists of the places reached are kept on context.allocator while it runs, and freed before it returns.
 *
 * @param schema The schema, from parse.
 * @param place The type's place among the schema's types. A place that isn't one writes nothing, and gives null.
 * @param into The array the bytes are added to, grown with its own allocator; what it held already is left as it is.
 * @return Null when the whole schema was written, or place isn't a type; otherwise the allocator's error, and into's
 *     count is as it was.
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

/**
 * Compute the schema hash of the type at a place among a schema's, as schema.hash gives it for that type, so a value
 * of it can be checked against a reader's hash.
 *
 * The bytes are written on context.allocator while they're hashed, and freed after.
 *
 * @param schema The schema, from parse.
 * @param place The type's place among the schema's types.
 * @return BLAKE3-256 of the type's schema. All zeros without the memory to write it; for a place that isn't a type,
 *     the hash of no bytes, which matches no type's.
 */
hash_rooted :: fn(schema: ptr[Schema], place: usize) -> u8[32] {
    bytes : u8[..]
    defer runtime.array_free(&bytes)
    if write_rooted(schema, place, &bytes) != null {
        nothing : u8[32]
        return nothing
    }
    return runtime.hash_blake3(bytes)
}

/**
 * Add bytes to the end of an array, stopping at the first that doesn't fit.
 *
 * @param into The array, grown with its own allocator.
 * @param bytes The bytes, in order.
 * @return Null when every byte was added; otherwise the allocator's error, with the bytes before it left added.
 */
add_all :: fn(into: ptr[mut u8[..]], bytes: u8[]) -> runtime.AllocatorError? {
    for byte in bytes {
        error :: runtime.array_try_add(into, byte)
        if error != null {
            return error
        }
    }
    return null
}

/**
 * Add a number to the end of an array, little-endian, as the schema's bytes are.
 *
 * @param into The array, grown with its own allocator.
 * @param value The number; only its low count bytes are written.
 * @param count How many bytes, 1 to 8.
 * @return Null when every byte was added; otherwise the allocator's error, with the bytes before it left added.
 */
add_number :: fn(into: ptr[mut u8[..]], value: u64, count: usize) -> runtime.AllocatorError? {
    for i in cast[usize](0)..<count {
        error :: runtime.array_try_add(into, cast[u8]((value >> (8 * cast[u64](i))) & 0xff))
        if error != null {
            return error
        }
    }
    return null
}

/**
 * Read the types of a schema's bytes, each in turn, into its types.
 *
 * @param schema The schema, with its bytes and no types yet; the types read are added even when it fails, for free to
 *     give back.
 * @return True when the header is right, the count is 1 to MAX_TYPES, every type is whole and nothing follows the
 *     last; false otherwise.
 */
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

/**
 * Read the type described at start into made.
 *
 * @param schema The schema whose bytes are read; the names made are views of them.
 * @param made Where what's read goes, with base and tag NOWHERE to start with; it's filled in as far as it's read,
 *     even when it fails.
 * @param start Where the description starts among the bytes.
 * @param count How many types the schema has, which every place it refers to has to be less than.
 * @return Where its description ends; NOWHERE if it's cut short, of a kind there isn't, has an array dimension of a
 *     kind there isn't, or refers to a place past count.
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

/**
 * Read a little-endian number from the bytes and move past it.
 *
 * @param bytes The bytes being read, such as a schema's; only read.
 * @param at Where it is, moved past it; NOWHERE given stays NOWHERE.
 * @param count How many bytes, 1 to 8.
 * @return The number; 0, with NOWHERE in at, if at was NOWHERE already or the bytes aren't all there.
 */
number_at :: fn(bytes: u8[], at: ptr[mut usize], count: usize) -> u64 {
    if at^ == NOWHERE || !fits(bytes, at^, count) {
        at^ = NOWHERE
        return 0
    }
    value :: read(bytes, at^, count)
    at^ += count
    return value
}

/**
 * Read a name, its count (u32) then its bytes, and move past it.
 *
 * @param schema The schema whose bytes it's in.
 * @param at Where it is, moved past it; NOWHERE given stays NOWHERE.
 * @return The name, a view of the schema's bytes, good until the schema is freed; "" for an empty name, or with
 *     NOWHERE in at when it's cut short.
 */
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

/**
 * Read a place another type is referred to by (u32), and note where it was as one of made's references.
 *
 * @param schema The schema whose bytes it's in.
 * @param made The type it's part of; the place's position is added to its references, with context.allocator, and
 *     without the memory, calls context.assertion_handler.
 * @param at Where it is, moved past it; set to NOWHERE if it's cut short or past count.
 * @param count How many types the schema has.
 * @return The place, less than count; NOWHERE if it's cut short or isn't one of the types.
 */
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

package compiler

/** One dimension of an array type, as TypeInfoArray lists them. */
ArrayDimensions :: struct {
    /** Whether this dimension is a static array, a dynamic array or a view. */
    type: ArrayType,
    /** How many elements a static array has; 0 for a dynamic array or a view, whose count is in the value. */
    count: usize,
    /** A view whose elements can be changed through it, mut T[]. */
    is_mutable: bool,
}

/** The kinds of array (docs/types.md, Arrays). */
ArrayType :: enum {
    /** T[n]: n elements held in place, n part of the type. */
    STATIC,
    /** T[..]: elements on the heap, which it owns and can grow. */
    DYNAMIC,
    /** T[]: a count and a pointer to elements something else holds. */
    VIEW,
}

/** The byte order a number is stored in. */
Endianness :: enum {
    /** Big-endian on every target, like u32be. */
    BIG,
    /** Little-endian on every target, like u32le. */
    LITTLE,
    /** The target's own order, as every number type without be or le is. */
    SYSTEM,
}

/** A parameter of a function type. */
FunctionInput :: struct {
    /** Its type. */
    type: ptr[TypeInfo],
    /** Its name; empty for a parameter written without one. */
    name: string,
    /** Whether it takes the rest of the arguments, as a parameter written with ... after its type does. */
    is_varargs: bool,
    /** Marked #escaping, which is part of the function's type. */
    is_escaping: bool,
}

/** A result of a function type. */
FunctionOutput :: struct {
    /** Its type. */
    type: ptr[TypeInfo],
}

/** One of a union's variants. */
UnionVariant :: struct {
    /** Its name, like Some. */
    name: string,
    /**
     * The types of the variant's values, like int and string for Pair(int, string); none for a
     * variant without values.
     */
    types: ptr[TypeInfo][],
    /** Each value's byte offset from the start of the union, after the tag, in the same order. */
    offsets: usize[],
}

/** One of a struct's members. */
StructMember :: struct {
    /** Its name. */
    name: string,
    /** Its type. */
    member_type: ptr[TypeInfo],
    /** Byte offset from the start of the struct, 0 for every member of a #union. */
    offset: usize,
    /** The default value, if has_value. Not filled in at run time yet: an empty any. */
    value: any,
    /** Whether it has a default value. */
    has_value: bool,
    /** Declared with using, so its own members are reached as the struct's. */
    is_using: bool,
}

/** Which kind of type a TypeInfo describes, and so which struct to cast it to for the rest. */
TypeInfoVariant :: enum {
    /** An alias: TypeInfoAlias. */
    ALIAS,
    /** any, which has nothing more than TypeInfo. */
    ANY,
    /** A static array, dynamic array or view: TypeInfoArray. */
    ARRAY,
    /** b8 to b64 and bool, which have nothing more than TypeInfo. */
    BOOLEAN,
    /** char, which has nothing more than TypeInfo. */
    CHAR,
    /** c32, c64 or c128, which have nothing more than TypeInfo. */
    COMPLEX,
    /** An enum: TypeInfoEnum. */
    ENUM,
    /** A float: TypeInfoFloat. */
    FLOAT,
    /** A function type: TypeInfoFunction. */
    FUNCTION,
    /** An integer: TypeInfoInteger. */
    INTEGER,
    /** A pointer, rawptr or relative pointer: TypeInfoPointer. */
    POINTER,
    /** q64, q128 or q256, which have nothing more than TypeInfo. */
    QUATERNION,
    /** string or cstring: TypeInfoString. */
    STRING,
    /** A struct: TypeInfoStruct. */
    STRUCT,
    /** type, which has nothing more than TypeInfo. */
    TYPE,
    /** A union, optionals and results included: TypeInfoUnion. */
    UNION,
    /** A vector, or v128 to v512: TypeInfoVector. */
    VECTOR,
    /** No type of its own, which has nothing more than TypeInfo. */
    VOID,
}

/**
 * The start of every type's description, which type_info_of gives a pointer to; variant says which struct the whole
 * description is.
 */
TypeInfo :: struct {
    /** Which kind of type it is, and so which struct to cast the pointer to. */
    variant : TypeInfoVariant,
    /** The size of the type's values in bytes, as size_of gives. */
    size: usize,
}

/** An alias's description. */
TypeInfoAlias :: struct {
    using TypeInfo,
    /** The type it names. */
    base_type: ptr[TypeInfo],
    /** The alias's name. */
    name: string,
    /** Declared distinct, so it's a type of its own rather than the type it names. */
    is_distinct: bool,
}

/** An array's description, all its dimensions in one. */
TypeInfoArray :: struct {
    using TypeInfo,
    /** The element type, the first one inside the dimensions that isn't an array. */
    base_type: ptr[TypeInfo],
    /** Outermost first, the one indexed first. */
    dimensions: ArrayDimensions[],
}

/** An enum's description. */
TypeInfoEnum :: struct {
    using TypeInfo,
    /** The enum's name. */
    name: string,
    /** From #backed_by, uint if it wasn't given. */
    backing_type: ptr[TypeInfo],
    /** Each member's name, in declaration order. */
    members: string[],
    /** The value of each member, in the same order as members. */
    values: u128[],
}

/** A float's description. */
TypeInfoFloat :: struct {
    using TypeInfo,
    /** The byte order it's stored in. */
    endianness: Endianness,
}

/** A function type's description. */
TypeInfoFunction :: struct {
    using TypeInfo,
    /** Its parameters, in order. */
    input: FunctionInput[],
    /** Its results, in order; empty when it returns nothing. */
    output: FunctionOutput[],
    /** Marked #never_returns. */
    never_returns: bool,
}

/**
 * An integer's description: int, uint, usize and uintptr are described like the fixed-size integers they're laid out
 * as, and told apart by comparing type values.
 */
TypeInfoInteger :: struct {
    using TypeInfo,
    /** Whether it holds negative numbers. */
    is_signed: bool,
    /** The byte order it's stored in. */
    endianness: Endianness,
}

/** A pointer's description: ptr[T], rawptr or a relative pointer. */
TypeInfoPointer :: struct {
    using TypeInfo,
    /** What it points to, none for rawptr. */
    base_type: ptr[TypeInfo]?,
    /** A relative pointer, relptr8 to relptr64, holding an offset from its own address. */
    is_relative: bool,
    /** Whether what it points to can be changed through it: ptr[mut T] or mut rawptr. */
    is_mutable: bool,
}

/** vector[T, n], or v128 to v512 (is_bits), which are lanes of u64 (docs/types.md, Vectors). */
TypeInfoVector :: struct {
    using TypeInfo,
    /** Each lane's type. */
    element_type: ptr[TypeInfo],
    /** How many lanes, a power of two. */
    count: usize,
    /** v128, v256 or v512: bits of a vector register, without lanes of their own. */
    is_bits: bool,
}

/** A string type's description. */
TypeInfoString :: struct {
    using TypeInfo,
    /** A cstring: a pointer to null-terminated text, rather than a count and a pointer. */
    is_raw: bool,
}

/** A struct's description. */
TypeInfoStruct :: struct {
    using TypeInfo,
    /** The struct's name; empty for one without. */
    name: string,
    /** Its members, in declaration order. */
    members: StructMember[],
    /** In bytes, from #align(n) if it was given, otherwise the natural alignment. */
    alignment: usize,
    /** Marked #scoped, so values hold pointers into the stack and can't be stored on the heap. */
    is_scoped: bool,
    /** Marked #unrestricted, so values never point into the stack and can be stored anywhere. */
    is_unrestricted: bool,
    /** Marked #packed, so there is no padding between members. */
    is_packed: bool,
    /** Marked #union, so every member is at offset 0 and they share memory. */
    is_union: bool,
    /** Marked #secret, so its values are secrets, which formatting shows as <secret> (docs/memory.md, Secrets). */
    is_secret: bool,
}

/** A union's description, optionals and results included. */
TypeInfoUnion :: struct {
    using TypeInfo,
    /** The union's name, like an instance's Optional[int]; empty for one without. */
    name: string,
    /** Its variants, in declaration order: a variant's tag is its index. */
    variants: UnionVariant[],
    /**
     * The unsigned integer at offset 0 saying which variant a value is: its index in variants.
     * None when null_is_none.
     */
    tag_type: ptr[TypeInfo]?,
    /**
     * An optional of a pointer that's never null, like ptr[T]? or cstring?: just the pointer,
     * null for None and anything else for Some, with no tag.
     */
    null_is_none: bool,
}

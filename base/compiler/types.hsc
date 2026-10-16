package compiler

ArrayDimensions :: struct {
    type: ArrayType,
    count: usize,
}

ArrayType :: enum {
    STATIC,
    DYNAMIC,
    VIEW,
}

Endianness :: enum {
    BIG,
    LITTLE,
    SYSTEM,
}

FunctionInput :: struct {
    type: ptr[TypeInfo],
    name: string,
    is_varargs: bool,
    // Marked #escaping, which is part of the function's type.
    is_escaping: bool,
}

FunctionOutput :: struct {
    type: ptr[TypeInfo],
}

UnionVariant :: struct {
    name: string,
    // The types of the variant's values, like int and string for Pair(int, string); none for a
    // variant without values.
    types: ptr[TypeInfo][],
    // Each value's byte offset from the start of the union, after the tag, in the same order.
    offsets: usize[],
}

StructMember :: struct {
    name: string,
    member_type: ptr[TypeInfo],
    // Byte offset from the start of the struct, 0 for every member of a #union.
    offset: usize,
    // The default value, if has_value. Not filled in at run time yet: an empty any.
    value: any,
    has_value: bool,
    is_using: bool,
}

TypeInfoVariant :: enum {
    ALIAS,
    ANY,
    ARRAY,
    BOOLEAN,
    CHAR,
    COMPLEX,
    ENUM,
    FLOAT,
    FUNCTION,
    INTEGER,
    POINTER,
    QUATERNION,
    STRING,
    STRUCT,
    TYPE,
    UNION,
    VOID,
}

TypeInfo :: struct {
    variant : TypeInfoVariant,
    size: usize,
}

TypeInfoAlias :: struct {
    using TypeInfo,
    base_type: ptr[TypeInfo],
    name: string,
    is_distinct: bool,
}

TypeInfoArray :: struct {
    using TypeInfo,
    base_type: ptr[TypeInfo],
    // Outermost first, the one indexed first.
    dimensions: ArrayDimensions[],
}

TypeInfoEnum :: struct {
    using TypeInfo,
    name: string,
    // From #backed_by, uint if it wasn't given.
    backing_type: ptr[TypeInfo],
    members: string[],
    // The value of each member, in the same order as members.
    values: u128[],
}

TypeInfoFloat :: struct {
    using TypeInfo,
    endianness: Endianness,
}

TypeInfoFunction :: struct {
    using TypeInfo,
    input: FunctionInput[],
    output: FunctionOutput[],
    // Marked #never_returns.
    never_returns: bool,
}

TypeInfoInteger :: struct {
    using TypeInfo,
    is_signed: bool,
    endianness: Endianness,
}

TypeInfoPointer :: struct {
    using TypeInfo,
    // What it points to, none for rawptr.
    base_type: ptr[TypeInfo]?,
    is_relative: bool,
    is_mutable: bool,
}

TypeInfoString :: struct {
    using TypeInfo,
    is_raw: bool,
}

TypeInfoStruct :: struct {
    using TypeInfo,
    name: string,
    members: StructMember[],
    // In bytes, from #align(n) if it was given, otherwise the natural alignment.
    alignment: usize,
    // Marked #scoped, so values hold pointers into the stack and can't be stored on the heap.
    is_scoped: bool,
    // Marked #unrestricted, so values never point into the stack and can be stored anywhere.
    is_unrestricted: bool,
    // Marked #packed, so there is no padding between members.
    is_packed: bool,
    // Marked #union, so every member is at offset 0 and they share memory.
    is_union: bool,
}

TypeInfoUnion :: struct {
    using TypeInfo,
    name: string,
    variants: UnionVariant[],
    // The unsigned integer at offset 0 saying which variant a value is: its index in variants.
    // None when null_is_none.
    tag_type: ptr[TypeInfo]?,
    // An optional of a pointer that's never null, like ptr[T]? or cstring?: just the pointer,
    // null for None (the second variant) and anything else for Some, with no tag.
    null_is_none: bool,
}


package compiler

ArrayDimensions :: struct {
    type: ArrayType,
    count: u64,
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
}

FunctionOutput :: struct {
    type: ptr[TypeInfo],
}

StructMember :: struct {
    name: string,
    member_type: ptr[TypeInfo],
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
    size: u64,
}

TypeInfoAlias :: struct {
    using TypeInfo,
    base_type: ptr[TypeInfo],
    name: string,
    distinct: bool,
}

TypeInfoArray :: struct {
    using TypeInfo,
    base_type: ptr[TypeInfo],
    dimensions: ArrayDimensions[],
}

TypeInfoEnum :: struct {
    using TypeInfo,
    name: string,
    members: string[],
}

TypeInfoFloat :: struct {
    using TypeInfo,
    endianness: Endianness,
}

TypeInfoFunction :: struct {
    using TypeInfo,
    input: FunctionInput[],
    output: FunctionOutput[],
}

TypeInfoInteger :: struct {
    using TypeInfo,
    is_signed: bool,
    endianness: Endianness,
}

TypeInfoPointer :: struct {
    using TypeInfo,
    base_type: ptr[TypeInfo],
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
}

TypeInfoUnion :: struct {
    using TypeInfo,
    name: string,
    variants: Map[string, string[]],
}


package reflection

as_string :: fn(value: any) -> (result: string, valid: bool) {
    //TODO(ches) convert to string
}

/*
 * The name of the enum member value holds, or none if it isn't an enum or matches no member.
 * Lets compile-time checks compare enum values from another program by name, since the
 * enum type itself differs between programs.
 */
enum_member_name :: fn(value: any) -> string? {
    //TODO look up the member through type_info_of
}

// Whether a and b have the same type and value, comparing structs and arrays member by member.
equal :: fn(a, b: any) -> bool {
    //TODO compare through type_info_of
}
package compiler

FunctionInfo :: struct {
    package_ : string,
    name : string,
    location : SourceCodeLocation,
    // Marked #export, so part of the library's or program's public interface.
    is_exported : bool,
    // False for bodiless --- declarations, like intrinsics and interface packages.
    has_body : bool,
    generic_bindings : GenericBinding[],
    parameters : FunctionParameter[],
    return_values : FunctionReturnValue[],
    // Every call in the body, in source order. Empty without a body.
    calls : FunctionCall[],
    // Every type the body uses, once each at its first use. Empty without a body.
    used_types : TypeUse[],
}

FunctionCall :: struct {
    // Canonical path of the called function's package, empty for a call through a function value.
    package_path : string,
    // Empty for a call through a function value.
    name : string,
    // The called function's type, which is all that is known for a call through a function value.
    type_ : type,
    location : SourceCodeLocation,
}

TypeUse :: struct {
    type_ : type,
    location : SourceCodeLocation,
}

FunctionParameter :: struct {
    name : string,
    type_ : type,
    default_value : any?,
    // Marked #escaping, so the function may keep it after returning.
    is_escaping : bool,
    is_varargs : bool,
}

FunctionReturnValue :: struct {
    name : string?,
    type_ : type,
}

GenericBinding :: struct {
    original_name : string,
    value : type,
}

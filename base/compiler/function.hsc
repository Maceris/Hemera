package compiler

FunctionInfo :: struct {
    package_ : string,
    name : string,
    location : SourceCodeLocation,
    // Marked #export, so part of the library's or program's public interface.
    is_exported : bool,
    generic_bindings : GenericBinding[],
    parameters : FunctionParameter[],
    return_values : FunctionReturnValue[],
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

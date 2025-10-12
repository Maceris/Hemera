package compiler

FunctionInfo :: struct {
    package :: string,
    name :: string,
    generic_bindings :: GenericBinding[],
    parameters :: FunctionParameter[],
    return_values :: ReturnValue[],
}

FunctionParameter :: struct {
    name :: string,
    type_ :: type,
    default_value :: any?,
}

FunctionReturnValue :: struct {
    name :: string?,
    type_ :: type,
}

GenericBinding :: struct {
    original_name :: string,
    value :: type,
}

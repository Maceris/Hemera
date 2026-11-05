package compiler

/**
 * A function as seen by compile-time code, from find_function or a PackageInfo's functions: its signature, its
 * documentation, and what its checked body calls and uses, for checks of house rules.
 */
FunctionInfo :: struct {
    /** Canonical path of the folder of the package that declares it. */
    package : string,
    /** Its name, as declared. */
    name : string,
    /** Where it's declared. */
    location : SourceCodeLocation,
    /** Marked #export, so part of the library's or program's public interface. */
    is_exported : bool,
    /** Marked #test, so a test a runner finds (docs/testing.md); it's compiled into a program only if something calls it. */
    is_test : bool,
    /**
     * For #test(CASES), the name its cases are given by, a constant array of its package's, each run as a test of its
     * own (docs/testing.md, Tests Over Cases); empty for a #test without them, or a function that isn't one.
     */
    test_cases : string,
    /** False for bodiless --- declarations, like intrinsics and interface packages. */
    has_body : bool,
    /** Marked #never_returns. */
    never_returns : bool,
    /** The function's own type, its signature as a type, like type_of(function) gives. */
    type : type,
    /**
     * For an instance of a generic function, like the pick[int] a FunctionCall names, each generic parameter that
     * takes a type, in the order the generic declares them, with the type it's bound to. A parameter that takes a
     * compile-time value isn't in it. Empty for a function that isn't an instance, the generic itself included.
     */
    generic_bindings : GenericBinding[],
    /** Each parameter, in order. */
    parameters : FunctionParameter[],
    /** Each result, in order; empty for a function that returns nothing. */
    return_values : FunctionReturnValue[],
    /** Every call in the body, in source order. Empty without a body. */
    calls : FunctionCall[],
    /** Every type the body uses, once each at its first use. Empty without a body. */
    used_types : TypeUse[],
    /** Every value the body discards with _ =, its type, at the _, in source order. Empty without a body. */
    discards : TypeUse[],
    /** Its documentation comment, parsed; empty without one (docs/documentation.md). */
    documentation : Documentation,
}

/**
 * A declaration's documentation comment (docs/documentation.md), parsed: everything empty for one without a comment.
 */
Documentation :: struct {
    /** Its summary: its @brief, or its first sentence. */
    brief : string,
    /** The rest of its text, its paragraphs separated by blank lines. */
    details : string,
    /** Its tags, @brief's aside, in order. */
    tags : DocumentationTag[],
}

/** One tag of a documentation comment, like @param count How many. */
DocumentationTag :: struct {
    /** Its name without the @: param, tparam, return, error, note, see, example, deprecated or since. */
    tag : string,
    /** What it documents, for @param, @tparam and @error; empty for the others. */
    name : string,
    /** Its text, after the name for those that have one, its lines' margins taken off; @example's lines are kept. */
    text : string,
}

/** A call in a function's body. */
FunctionCall :: struct {
    /** Canonical path of the called function's package, empty for a call through a function value. */
    package_path : string,
    /** Empty for a call through a function value. */
    name : string,
    /** The called function's type, which is all that is known for a call through a function value. */
    type : type,
    /** Where the call is: its function's name, or the function value. */
    location : SourceCodeLocation,
}

/** A type used in a function's body, and where. */
TypeUse :: struct {
    /** The type, as the body uses it. */
    type : type,
    /** Where it's used. */
    location : SourceCodeLocation,
}

/** A function's parameter. */
FunctionParameter :: struct {
    /** Its name, as declared. */
    name : string,
    /** Its type. */
    type : type,
    /**
     * Its default's value, of the parameter's type, for a default that's the same at every call: a literal, a
     * constant, an enum member, a struct literal of those. None without a default, for one that can differ between
     * calls (#caller_location, the context, or a call), for one that can't be kept, like a function, and while the
     * function's body isn't checked yet, as when its own package's #run code asks.
     */
    default_value : any?,
    /** Marked #escaping, so the function may keep it after returning. */
    is_escaping : bool,
    /** Whether it takes the rest of the arguments, as a parameter written with ... after its type does. */
    is_varargs : bool,
    /** Its function's documentation's @param for it; empty without one. */
    documentation : string,
}

/** A function's result. */
FunctionReturnValue :: struct {
    /** Its name, for a named result; None for one without. */
    name : string?,
    /** Its type. */
    type : type,
    /** What its function's documentation says of it: its @return's text, without its name; empty without one. */
    documentation : string,
}

/** A generic parameter and what it's bound to. */
GenericBinding :: struct {
    /** The generic parameter's name, as declared. */
    original_name : string,
    /** The type it's bound to. */
    value : type,
}

package compiler

import runtime from "base"

/**
 * A location in the source code, what #caller_location gives: runtime's, so a location from either
 * package is the same type.
 */
SourceCodeLocation :: runtime.SourceCodeLocation

/**
 * Code: a syntax tree the compiler keeps, which compile-time code holds by handle (docs/compilation.md,
 * Code Values). #code { ... } and #code(...) make one from Hemera written in place, parsed but not
 * checked, with #insert inside putting values in it when the quote is evaluated. Only compile-time code
 * has them: like a pointer, a Code can't reach the program.
 */
Code :: struct {
    /**
     * Numbered from 1 within the compile-time code that made it, whatever else ran meanwhile, so a
     * build that reads it comes out the same each time. Its trees are freed with the program.
     */
    handle : u64,
}

/**
 * Give Hemera source for code, formatted for reading, as --show-inserted prints it.
 *
 * @param code The code, from a quote or one of the functions below.
 * @return The source, which parses back into the same tree.
 */
code_text : fn(code: Code) -> string : ---

/**
 * Make what #code evaluates to; the compiler writes the calls, for each quote.
 *
 * @param quote Which quote, as the compiler identifies it; only the calls the compiler writes have one.
 * @param splices The values of the quote's #inserts, in order: a Code is its tree, a type the type itself, and a
 *     number, boolean, character, string or enum member a literal of it.
 * @return A copy of the quote's tree, with each #insert in it replaced by its splice.
 */
quote_code : fn(quote: u64, splices: any[]) -> Code : ---

/*
 * Code made from values rather than quoted, for what a quote can't say, like a name from a table. Each comes from
 * where it's called, which is where errors in it are reported.
 */

/**
 * Make a name from parts joined, like name("atomic_load_", "u64"), for a declaration's or member's name a quote
 * can't spell.
 *
 * @param parts The pieces of text, joined with nothing between them.
 * @param location Where an error in it is reported; the caller's own by default.
 * @return The name, which is an identifier, never anything else. If the joined text isn't one (letters, digits and
 *     _, not starting with a digit, and not a keyword), it's an error at location.
 */
name : fn(parts: string..., location := #caller_location) -> Code : ---

/**
 * Make a literal of a value.
 *
 * @param value A number, boolean, character, string or enum member; anything else is an error at location.
 * @param location Where an error in it is reported; the caller's own by default.
 * @return The literal, of the value's type.
 */
literal : fn(value: any, location := #caller_location) -> Code : ---

/**
 * Make code of a type, as itself, so nothing is looked up by its name where it goes.
 *
 * @param T The type.
 * @param location Where an error in it is reported; the caller's own by default.
 * @return The type's code, for where a type goes, like -> #insert T.
 */
type_code : fn(T: type, location := #caller_location) -> Code : ---

/**
 * Make a list of code: inserted, its items go in its place, each one of what holds it, like arguments or statements.
 *
 * @param items The items, in order. Statements given, and lists, give their own items rather than being one each;
 *     items that hold no code are left out.
 * @param location Where an error in it is reported; the caller's own by default.
 * @return The list, empty when items is.
 */
list : fn(items: Code[], location := #caller_location) -> Code : ---

/**
 * Give the type a type's description is of, as a type value, for what takes a type, like a struct member's type from
 * type_info_of.
 *
 * @param info A description from type_info_of, or reached through one.
 * @return The type it describes.
 */
described_type : fn(info: ptr[TypeInfo]) -> type : ---

/**
 * Make a function type's parameters into a parameter list, as name: Type, for fn(#insert parameters(F)).
 *
 * @param function A function type; anything else is an error at location.
 * @param location Where an error in it is reported; the caller's own by default.
 * @return The parameters, in order. One without a name is called p and its place, like p0; arguments gives the same
 *     names.
 */
parameters : fn(function: type, location := #caller_location) -> Code : ---

/**
 * Make a function type's parameters' names into a list of arguments, for a call passing them on.
 *
 * @param function A function type; anything else is an error at location.
 * @param location Where an error in it is reported; the caller's own by default.
 * @return The names, in order, as parameters names them.
 */
arguments : fn(function: type, location := #caller_location) -> Code : ---

/** What a piece of code is, for code that takes code, like a macro. */
CodeKind :: enum {
    /** One expression, like #code(a + b). */
    Expression,
    /** Statements or declarations, like #code { ... }. */
    Statements,
    /** A name, like name() makes. */
    Name,
    /** A type, like type_code() makes. */
    Type,
    /** A literal, like literal() makes. */
    Literal,
    /** A list, whose items go in its place, like list() makes. */
    List,
    /** A struct's fields, from #code fields { ... }. */
    Fields,
    /** A union's variants, from #code variants { ... }. */
    Variants,
    /** An enum's members, from #code members { ... }. */
    Members,
    /** A match's patterns, each with what it runs, from #code patterns { ... }. */
    Patterns,
    /** A switch's cases, from #code cases { ... }. */
    Cases,
}

/**
 * Tell what a piece of code is.
 *
 * @param code The code.
 * @return Its kind.
 */
code_kind : fn(code: Code) -> CodeKind : ---

/**
 * Give a name's text.
 *
 * @param code The code.
 * @return The name's text when code is a Name; none for other code.
 */
identifier_of : fn(code: Code) -> string? : ---

/**
 * Give the items of code that has them.
 *
 * @param code The code.
 * @return Each item of statements, a list, fields, variants, members, patterns or cases, in order, each its own Code;
 *     empty for other code.
 */
items_of : fn(code: Code) -> Code[] : ---

/**
 * Give where code was written, or made.
 *
 * @param code The code.
 * @return The quote's location, or for code from name, literal and the like, where that was called.
 */
location_of : fn(code: Code) -> SourceCodeLocation : ---

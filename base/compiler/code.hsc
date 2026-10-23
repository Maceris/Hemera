package compiler

import runtime from "base"

/*
 * A location in the source code, what #caller_location gives: runtime's, so a location from either
 * package is the same type.
 */
SourceCodeLocation :: runtime.SourceCodeLocation

/*
 * Code: a syntax tree the compiler keeps, which compile-time code holds by handle (docs/compilation.md,
 * Code Values). #code { ... } and #code(...) make one from Hemera written in place, parsed but not
 * checked, with #insert inside putting values in it when the quote is evaluated. Only compile-time code
 * has them: like a pointer, a Code can't reach the program.
 */
Code :: struct {
    // Numbered from 1 within the compile-time code that made it, whatever else ran meanwhile, so a
    // build that reads it comes out the same each time. Its trees are freed with the program.
    handle : u64,
}

// Hemera source for code, formatted for reading. It parses back into the same tree.
code_text : fn(code: Code) -> string : ---

// What #code evaluates to: the quote at quote, a copy, with each #insert in it replaced by splices' values in order.
quote_code : fn(quote: u64, splices: any[]) -> Code : ---

/*
 * Code made from values rather than quoted, for what a quote can't say, like a name from a table. Each comes from
 * where it's called, which is where errors in it are reported.
 */

// A name: an identifier, never anything else, or an error there if text isn't one (letters, digits and _, not
// starting with a digit, and not a keyword).
name : fn(text: string, location := #caller_location) -> Code : ---

// A literal of a number, boolean, character, string or enum member.
literal : fn(value: any, location := #caller_location) -> Code : ---

// A type, as itself, so nothing is looked up by its name where it goes.
type_code : fn(T: type, location := #caller_location) -> Code : ---

// A list of code: inserted, its items go in its place, each one of what holds it, like arguments or statements.
// Statements given, and lists, give their own items.
list : fn(items: Code[], location := #caller_location) -> Code : ---

// The type info describes, as a type value, for what takes a type, like a struct member's type from type_info_of.
described_type : fn(info: ptr[TypeInfo]) -> type : ---

// A function type's parameters, as a list of name: Type, for a function's parameter list. One without a name is
// called p and its place, like p0.
parameters : fn(function: type, location := #caller_location) -> Code : ---

// A function type's parameters' names, as a list of arguments, for a call passing them on.
arguments : fn(function: type, location := #caller_location) -> Code : ---

// What a piece of code is, for code that takes code, like a macro.
CodeKind :: enum {
    Expression,
    Statements,
    Name,
    Type,
    Literal,
    List,
    Fields,
    Variants,
    Members,
    Patterns,
    Cases,
}

code_kind : fn(code: Code) -> CodeKind : ---

// A Name's text, or none for other code.
identifier_of : fn(code: Code) -> string? : ---

// Each item of statements, a list, fields, variants, members, patterns or cases; none for other code.
items_of : fn(code: Code) -> Code[] : ---

// Where the code was written, or made.
location_of : fn(code: Code) -> SourceCodeLocation : ---

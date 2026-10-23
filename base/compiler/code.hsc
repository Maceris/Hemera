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

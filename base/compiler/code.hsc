package compiler

/*
 * A location in the source code. This is what #caller_location refers to,
 * and mirrors token information that the compiler tracks.
 */
SourceCodeLocation :: struct {
    file_name: string,
    line_number: u32,
    column_number: u16,
}

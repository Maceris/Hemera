/*
 * Typed libraries (docs/compilation.md, Typed Libraries): a build package that builds the maths package as a typed
 * library, and a program that calls it, where the test's "library" and "program" settings say. The program's main
 * returns 42 if every call through the library gave what it should.
 */
package build

import compiler from "base"
import runtime from "base"

build :: fn() {
    maths := compiler.command_line_options()
    maths.name = "maths"
    maths.root = "../maths"
    maths.output_path = compiler.target_setting("library")
    maths.target_options.output_type = .DynamicLibrary
    _ = compiler.add_target(maths)

    program := compiler.command_line_options()
    program.name = "program"
    program.root = "../program"
    program.output_path = compiler.target_setting("program")
    runtime.array_add(&program.libraries, compiler.LinkedLibrary.{target = "maths"})
    _ = compiler.add_target(program)
}

#run build()

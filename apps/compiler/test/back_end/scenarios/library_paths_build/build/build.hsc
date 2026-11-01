/*
 * A build package for the back end's test giving its target a library folder, from the "libs" setting, which the test
 * points at the folder it made the import library in.
 */
package build

import compiler from "base"
import runtime from "base"

build :: fn() {
    options := compiler.command_line_options()
    options.name = "library_paths"
    options.root = "../../library_paths"
    options.output_path = compiler.target_setting("output")
    runtime.array_add(&options.target_options.library_paths, compiler.target_setting("libs"))
    target :: compiler.add_target(options)
}

#run build()

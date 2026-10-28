/*
 * The changed maths library (changed_maths), built where the test's "library" setting says, over the first one, for
 * the Linux tests: the program built against the first refuses it, naming add.
 */
package build_changed

import compiler from "base"

build :: fn() {
    maths := compiler.command_line_options()
    maths.name = "maths"
    maths.root = "../changed_maths"
    maths.output_path = compiler.target_setting("library")
    maths.target_options.output_type = .DynamicLibrary
    _ = compiler.add_target(maths)
}

#run build()

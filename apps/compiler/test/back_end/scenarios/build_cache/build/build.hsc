/*
 * A build package for the build cache's test (docs/compilation.md, The Build Cache): its one target's check reads a
 * file and writes what it read to another, both named by settings, and its app is built from a file of its own with
 * #file_data, so the test can change each and see what's built again. Nothing is reported, so its build is kept.
 */
package build

import compiler from "base:compiler"
import os from "std:os"

copy_data :: fn(target : ptr[compiler.BuildOptions], program : ptr[compiler.ProgramInfo]) -> bool {
    // A check writes nothing
    if compiler.checking() {
        return true
    }
    read := ""
    match os.read_entire_file(compiler.target_setting("data")) {
        case Ok(bytes) => read = bytes
        case Error(error) => return false
    }
    return os.write_entire_file(compiler.target_setting("written"), read) == null
}

build :: fn() {
    app := compiler.command_line_options()
    app.name = "app"
    app.root = "../app"
    app.output_path = compiler.target_setting("output")
    target :: compiler.add_target(app)
    compiler.add_check(copy_data)
}

#run build()

/*
 * A build package for the back end's test that finds what to build: each folder in programs is loaded, and
 * built if it's a package whose KIND names Program. alpha is; beta is a library; notes isn't a package.
 * compiler.declares is asked of them too, from their files parsed alone: alpha declares main and beta doesn't, beta
 * declares only_sometimes in an #if branch no build takes, and notes, with no package files, and a folder that isn't
 * there declare nothing. A wrong answer is an error, which fails the test.
 */

package build

import compiler from "base:compiler"
import reflection from "std:reflection"

build :: fn() {
    for folder in compiler.subfolders("../programs") {
        package := compiler.load_package(folder) or_else compiler.PackageInfo.{}
        kind :: compiler.find_constant(&package, "KIND") or_else compiler.ConstantInfo.{}
        if package.name != "" && (reflection.enum_member_name(kind.value) or_else "") == "Program" {
            options := compiler.command_line_options()
            options.name = package.name
            options.root = package.path
            options.output_path = compiler.target_setting("output")
            target :: compiler.add_target(options)
        }
    }
    expect_declares("../programs/alpha", "main", true)
    expect_declares("../programs/alpha", "KIND", true)
    expect_declares("../programs/beta", "main", false)
    expect_declares("../programs/beta", "only_sometimes", true)
    expect_declares("../programs/beta", "helpe", false)
    expect_declares("../programs/notes", "main", false)
    expect_declares("../programs/missing", "main", false)
}

/** Report an error unless compiler.declares answers as expected. */
expect_declares :: fn(folder : string, name : string, expected : bool) {
    if compiler.declares(folder, name) != expected {
        compiler.report_error(#source_location, "compiler.declares(%, %) wasn't %", folder, name, expected)
    }
}

#run build()

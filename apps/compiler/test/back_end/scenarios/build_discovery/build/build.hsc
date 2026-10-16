/*
 * A build package for the back end's test that finds what to build: each folder in programs is loaded, and
 * built if it's a package whose KIND names Program. alpha is; beta is a library; notes isn't a package.
 */
package build

import compiler from "base"
import reflection from "std"

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
}

#run build()

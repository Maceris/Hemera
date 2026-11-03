package documentation

import compiler from "base"
import documented from "./documented"

/*
 * Documentation comments (docs/documentation.md), read back at compile time: a function's summary, details and tags,
 * its parameters' @param text, and a plain comment, which isn't documentation. main returns 42 if each holds.
 */

checked :: fn() -> int {
    info :: compiler.package_info("documented") or_else compiler.PackageInfo.{}
    found :: compiler.find_function(&info, "copy") or_else compiler.FunctionInfo.{}
    documentation :: found.documentation
    if documentation.brief != "Copies files into a directory." {
        return 1
    }
    if documentation.details != "Each one keeps its name.\n\nNothing is replaced unless asked." {
        return 2
    }
    if documentation.tags.count != 6 {
        return 3
    }
    error :: documentation.tags[4]
    if error.tag != "error" || error.name != "NoSpace" || error.text != "the volume filled" {
        return 4
    }
    if documentation.tags[3].tag != "return" || documentation.tags[5].text != "copy notes backup" {
        return 5
    }
    if found.parameters.count != 3 || found.parameters[1].documentation != "where they go, beneath the home" {
        return 6
    }
    unwritten :: compiler.find_function(&info, "plain") or_else compiler.FunctionInfo.{}
    if unwritten.documentation.brief != "" || unwritten.documentation.tags.count != 0 {
        return 7
    }
    briefed :: compiler.find_function(&info, "stated") or_else compiler.FunctionInfo.{}
    if briefed.documentation.brief != "Stated. And more." {
        return 8
    }
    // Each of several results' @return: a named one's by its name, an unnamed one's in turn
    reading :: compiler.find_function(&info, "read_some") or_else compiler.FunctionInfo.{}
    if reading.return_values.count != 2 || reading.return_values[0].documentation != "How many were read."
        || reading.return_values[1].documentation != "Why it stopped, or null." {
        return 12
    }
    halving :: compiler.find_function(&info, "halves") or_else compiler.FunctionInfo.{}
    if halving.return_values.count != 2 || halving.return_values[1].documentation != "Its low half." {
        return 13
    }
    // A type's, and its members' that have one, before them or after them on their lines
    reasons :: compiler.TypeDeclaration.{}
    for each in info.types {
        if each.name == "CopyError" {
            if each.documentation.brief != "Why a copy stopped." || each.members.count != 2 {
                return 9
            }
            if each.members[0].name != "NoSpace" || each.members[0].documentation.brief != "The volume filled."
                || each.members[1].name != "Missing" || each.members[1].documentation.brief != "Nothing was there." {
                return 10
            }
            return 42
        }
    }
    return 11
}

RESULT :: #run checked()

main :: fn() -> int {
    return RESULT
}

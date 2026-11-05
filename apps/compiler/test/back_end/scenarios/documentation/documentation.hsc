package documentation

import compiler from "base"
import testing from "std"
import documented from "./documented"

/*
 * Documentation comments (docs/documentation.md), read back at compile time: a function's summary, details and tags,
 * its parameters' @param text, and a plain comment, which isn't documentation. What's read is kept in a constant, which
 * the tests look at when the program runs.
 */

/** What reflection read of documented's documentation, at compile time; empty text and 0 for what wasn't found. */
Read :: struct {
    /** copy's summary. */
    brief : string,
    /** copy's details, its paragraphs separated by a blank line. */
    details : string,
    /** How many tags copy has. */
    tag_count : usize,
    /** copy's fifth tag's tag, name and text: its @error. */
    error_tag : string,
    /** The name its @error gives. */
    error_name : string,
    /** The text its @error gives. */
    error_text : string,
    /** copy's fourth tag's tag. */
    fourth_tag : string,
    /** copy's sixth tag's text. */
    sixth_text : string,
    /** How many parameters copy has. */
    parameter_count : usize,
    /** The second parameter's @param text. */
    second_parameter : string,
    /** plain's summary. */
    plain_brief : string,
    /** How many tags plain has. */
    plain_tag_count : usize,
    /** stated's summary. */
    stated_brief : string,
    /** How many results read_some has. */
    read_some_count : usize,
    /** read_some's first result's @return text. */
    read_some_first : string,
    /** read_some's second result's @return text. */
    read_some_second : string,
    /** How many results halves has. */
    halves_count : usize,
    /** halves' second result's @return text. */
    halves_second : string,
    /** Whether Wrapped was found among the types. */
    wrapped_found : bool,
    /** How many members Wrapped has. */
    wrapped_member_count : usize,
    /** Its first member's name. */
    wrapped_member_name : string,
    /** Its first member's summary. */
    wrapped_member_brief : string,
    /** Whether CopyError was found among the types. */
    copy_error_found : bool,
    /** CopyError's summary. */
    copy_error_brief : string,
    /** How many members CopyError has. */
    copy_error_member_count : usize,
    /** CopyError's first member's name. */
    first_member_name : string,
    /** CopyError's first member's summary, written before it. */
    first_member_brief : string,
    /** CopyError's second member's name. */
    second_member_name : string,
    /** CopyError's second member's summary, written after it on its line. */
    second_member_brief : string,
}

/**
 * Find a function by its name.
 *
 * @param functions The functions looked through, a package's.
 * @param name The function's name.
 * @return The first function named so; an empty FunctionInfo if there's none.
 */
named :: fn(functions: compiler.FunctionInfo[], name: string) -> compiler.FunctionInfo {
    for function in functions {
        if function.name == name {
            return function
        }
    }
    return compiler.FunctionInfo.{}
}

/**
 * Read documented's documentation through reflection, for READ.
 *
 * @return What was read; what wasn't found is left empty.
 */
read :: fn() -> Read {
    made := Read.{}
    info :: compiler.package_info("documented") or_else compiler.PackageInfo.{}
    found :: named(info.functions, "copy")
    documentation :: found.documentation
    made.brief = documentation.brief
    made.details = documentation.details
    made.tag_count = documentation.tags.count
    if documentation.tags.count == 6 {
        made.error_tag = documentation.tags[4].tag
        made.error_name = documentation.tags[4].name
        made.error_text = documentation.tags[4].text
        made.fourth_tag = documentation.tags[3].tag
        made.sixth_text = documentation.tags[5].text
    }
    made.parameter_count = found.parameters.count
    if found.parameters.count == 3 {
        made.second_parameter = found.parameters[1].documentation
    }
    unwritten :: named(info.functions, "plain")
    made.plain_brief = unwritten.documentation.brief
    made.plain_tag_count = unwritten.documentation.tags.count
    briefed :: named(info.functions, "stated")
    made.stated_brief = briefed.documentation.brief
    reading :: named(info.functions, "read_some")
    made.read_some_count = reading.return_values.count
    if reading.return_values.count == 2 {
        made.read_some_first = reading.return_values[0].documentation
        made.read_some_second = reading.return_values[1].documentation
    }
    halving :: named(info.functions, "halves")
    made.halves_count = halving.return_values.count
    if halving.return_values.count == 2 {
        made.halves_second = halving.return_values[1].documentation
    }
    for each in info.types {
        if each.name == "Wrapped" {
            made.wrapped_found = true
            made.wrapped_member_count = each.members.count
            if each.members.count == 1 {
                made.wrapped_member_name = each.members[0].name
                made.wrapped_member_brief = each.members[0].documentation.brief
            }
        }
        if each.name == "CopyError" {
            made.copy_error_found = true
            made.copy_error_brief = each.documentation.brief
            made.copy_error_member_count = each.members.count
            if each.members.count == 2 {
                made.first_member_name = each.members[0].name
                made.first_member_brief = each.members[0].documentation.brief
                made.second_member_name = each.members[1].name
                made.second_member_brief = each.members[1].documentation.brief
            }
        }
    }
    return made
}

READ :: #run read()

reads_a_functions_summary_and_details #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, READ.brief, "Copies files into a directory.", "the summary is the first sentence")
    testing.expect_eq(t, READ.details, "Each one keeps its name.\n\nNothing is replaced unless asked.",
        "the details are the rest before the tags, paragraphs kept apart")
    return .Ok
}

reads_a_functions_tags #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.require_eq(t, READ.tag_count, 6, "three @param, a @return, an @error and an @example")?
    testing.expect_eq(t, READ.error_tag, "error", "the fifth is the @error")
    testing.expect_eq(t, READ.error_name, "NoSpace", "an @error's first word is its name")
    testing.expect_eq(t, READ.error_text, "the volume filled", "and the rest its text")
    testing.expect_eq(t, READ.fourth_tag, "return", "the fourth is the @return")
    testing.expect_eq(t, READ.sixth_text, "copy notes backup", "an @example has no name, only text")
    return .Ok
}

gives_parameters_their_param_text #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.require_eq(t, READ.parameter_count, 3, "copy takes three parameters")?
    testing.expect_eq(t, READ.second_parameter, "where they go, beneath the home",
        "into's @param, its continued line joined to it")
    return .Ok
}

reads_no_documentation_from_a_plain_comment #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, READ.plain_brief, "", "a // comment isn't documentation")
    testing.expect_eq(t, READ.plain_tag_count, 0, "so there are no tags either")
    return .Ok
}

takes_a_brief_tag_whole #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, READ.stated_brief, "Stated. And more.", "@brief's text is the summary, past its first sentence")
    return .Ok
}

gives_each_result_its_return_text #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Each of several results' @return: a named one's by its name, an unnamed one's in turn
    testing.require_eq(t, READ.read_some_count, 2, "read_some has two results")?
    testing.expect_eq(t, READ.read_some_first, "How many were read.", "the @return naming count")
    testing.expect_eq(t, READ.read_some_second, "Why it stopped, or null.", "the @return naming error")
    testing.require_eq(t, READ.halves_count, 2, "halves has two results")?
    testing.expect_eq(t, READ.halves_second, "Its low half.", "unnamed, the second @return is the second result's")
    return .Ok
}

documents_a_field_included_with_using #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.require(t, READ.wrapped_found, "documented declares Wrapped")?
    testing.require_eq(t, READ.wrapped_member_count, 1, "a using field is one member")?
    testing.expect_eq(t, READ.wrapped_member_name, "inner", "named as declared")
    testing.expect_eq(t, READ.wrapped_member_brief, "The count inside, whose fields are the wrapper's.",
        "documented as any other field")
    return .Ok
}

documents_a_type_and_its_members #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // A type's, and its members' that have one, before them or after them on their lines
    testing.require(t, READ.copy_error_found, "documented declares CopyError")?
    testing.expect_eq(t, READ.copy_error_brief, "Why a copy stopped.", "a type's own documentation")
    testing.require_eq(t, READ.copy_error_member_count, 2, "CopyError has two members")?
    testing.expect_eq(t, READ.first_member_name, "NoSpace", "members in the order declared")
    testing.expect_eq(t, READ.first_member_brief, "The volume filled.", "documented before it")
    testing.expect_eq(t, READ.second_member_name, "Missing", "members in the order declared")
    testing.expect_eq(t, READ.second_member_brief, "Nothing was there.", "documented after it, with /**<")
    return .Ok
}

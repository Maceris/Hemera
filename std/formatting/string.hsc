package formatting

import string from "std"

FORMAT_PLACEHOLDER : char : '%'

FormatLocation :: struct {
    // Position in the input string
    location : usize,
    // -1 for an escaped placeholder, 0 for unspecified, 1/2/3... for first, second, etc. argument
    argument_number : i32,
}

find_format_locations :: fn(format: string, format_locations : mut FormatLocation[..], arg_count: usize) -> bool {
    has_positional : bool = false
    has_unspecified : bool = false
    with {
        index : usize = 0
        character : char
        found_placeholder : bool = false
    }
    loop {
        defer index += 1
        character = format[index]
        
        if character == FORMAT_PLACEHOLDER {
            if found_placeholder {
                // This is an escaped placeholder
                array_add(format_locations, FormatLocation.{index, -1})
                found_placeholder = false
            }
            else {
                found_placeholder = true
            }
        }
        else {
            if found_placeholder {
                // check for numbers

                if char_is_number(character) {
                    original_index := index
                    value : int = 0

                    with {
                        digit : int = 0
                        is_digit : bool = false
                    }
                    loop {
                        defer index += 1
                        character = format[index]
                        digit, is_digit = char_to_int(character)

                        if !is_digit {
                            break
                        }
                        value *= 10
                        value += digit
                    }
                    while char_is_number(character)

                    array_add(format_locations, FormatLocation.{original_index, value})
                    found_placeholder = false
                    has_positional = true
                }
                else {
                    // It was just a single placeholder, no number or escaped version
                    array_add(format_locations, FormatLocation.{index, 0})
                    has_unspecified = true
                }
            }
            // is not, and was not just, a placeholder. Keep going.
        }
    }
    while index < format.count

    if has_positional && has_unspecified {
        log_error("Cannot mix positional (%%1) and unspecified (%%) formats")
        return false
    }

    for match, index in format_locations {
        if match <= 0 {
            continue
        }
        if match > arg_count {
            log_error("Tried to log %'th argument but only had % arguments", match, arg_count)
            return false
        }
    }

    return true
}

format :: fn(format: string, args: any...) -> string {
    //TODO(ches) format string
    
    log_builder := new(StringBuilder)
    defer delete(log_builder)
    init_string_builder(log_builder)

    format_locations : FormatLocation[..]
    defer array_free(format_locations)
    array_reserve(format_locations, 8)

    valid: bool = find_format_locations(format, format_locations, args.count)

    //TODO(ches) we should check the validity of this at compile time where possible
    if !valid {
        append(log_builder, "Invalid format string: \"")
        append(log_builder, format)
        append(log_builder, '"')

        error_message :: builder_to_string(log_builder)
        log_warn(error_message)

        return format
    }

    input_index : usize = 0
    arg_index : usize = 0

    for match in format_locations {
        if match.location > 0 {
            // Everything before the match, after the start / last match
            before_match :: match.location - input_index
            append(log_builder, format, input_index, before_match)
            input_index += before_match
        }
        // And now the actual match
        if match.argument_number == -1 {
            // Just need a placeholder
            append(log_builder, FORMAT_PLACEHOLDER)
            input_index += 2
        }
        else if match.argument_number == 0 {
            // unspecified
            if arg_index >= args.count {
                log_error("Invalid argument count slipped past our checks")
                break
            }
            arg_string :: any_to_string(args[arg_index])
            append(log_builder, arg_string)

            input_index += 1
            arg_index += 1
        }
        else {
            // numbered
            if match.argument_number < 0 || match.argument_number >= args.count {
                log_error("Invalid argument number slipped past our checks")
                continue
            }
            arg_string :: any_to_string(args[match.argument_number])
            append(log_builder, arg_string)

            input_index += 1
            loop {
                if input_index > format.count {
                    break 2
                }
                current :: format[input_index]
                if char_is_number(current) {
                    input_index += 1
                }
                else {
                    break
                }
            }
        }
    }
    
    // Everything after final match
    if input_index < format.count {
        before_match :: format.count - input_index
        append(log_builder, format, input_index, before_match)
        input_index += before_match
    }

    result :: builder_to_string(log_builder)

    return result
    
}

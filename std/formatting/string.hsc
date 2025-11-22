package formatting

import string from "std"

FORMAT_PLACEHOLDER : char : '%'

FormatLocation :: struct {
    // Position in the input string
    location : u64,
    // -1 for an escaped placeholder, 0 for unspecified, 1/2/3... for first, second, etc. argument
    argument_number : i32,
}

find_format_locations :: fn(format: string, format_locations : mut FormatLocation[..], arg_count: u64) -> bool {
    has_positional : bool = false
    has_unspecified : bool = false
    with {
        index : u64 = 0
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
        // TODO(ches) Error, log this
        return false
    }

    for match, index in format_locations {
        if match <= 0 {
            continue
        }
        if match > arg_count {
            // TODO(ches) Error, log this
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
        //TODO(ches) bail
    }

    input_index : u64 = 0
    output_index : u64 = 0
    arg_index : u64 = 0

    for match in format_locations {
        if match.location > 0 {
            // Everything before the match, after the start / last match
            before_match :: match.location - input_index
            append(log_builder, input_index, before_match)
            input_index += before_match
            output_index += before_match
        }
        // And now the actual match
        if match.argument_number == -1 {
            // Just need a placeholder
        }
        else if match.argument_number == 0 {
            // unspecified
        }
        else {
            // numbered
        }
    }
    
    // Everything after final match
    if input_index < format.count {

    }

    
}

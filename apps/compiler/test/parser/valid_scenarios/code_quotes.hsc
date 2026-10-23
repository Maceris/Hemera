package valid_scenarios

// Quotes (docs/compilation.md, Code Values): of an expression, statements, and of what goes inside something else
sum :: #code(a + b)
statements :: #code {
    total := #insert sum * 2
    #insert more
}
position :: #code fields {
    x : f32,
    y : f32 = 1,
    #insert others,
}
shapes :: #code variants {
    Circle(f32),
    Empty,
    #insert others,
}
colors :: #code members {
    Red,
    Green = 2,
    #insert others,
}
results :: #code patterns {
    case .Red => 1
    case .Green, .Blue => {
        return 2
    }
    #insert others
}
// Names, parameters and types inserted, in a quote
stub :: #code {
    #insert name :: fn(#insert parameters, last: u8) -> #insert result {
        pointer : ptr[mut #insert element]
        return target(#insert arguments)
    }
}
numbers :: #code cases {
    case 1, 2:
        small()
    #insert others
    case 3:
        three()
}

// #insert among fields, variants, members, patterns and cases
Point :: struct #packed {
    #insert position_fields(),
    z : f32,
}
Shape :: union {
    Square(f32),
    #insert shape_variants(),
}
Color :: enum #backed_by(u8) {
    #insert color_members(),
    Blue,
}

describe :: fn(color: Color, n: int) -> int {
    switch n {
    case 0:
        nothing()
    #insert number_cases()
    }
    return match color {
        case .Blue => 3
        #insert color_patterns()
    }
}

#insert declarations()

// Macros (docs/compilation.md, Macros), and an assignment to what's inserted
swap #macro :: fn(a: compiler.Code, b: compiler.Code) -> compiler.Code {
    return #code {
        temporary := #insert a
        #insert a = #insert b
        #insert b += temporary
    }
}

use_macros :: fn() -> int {
    a := 1
    b := 2
    swap!(a, b)
    helpers.swap!(a, b)
    return twice!(a + b) * !done
}

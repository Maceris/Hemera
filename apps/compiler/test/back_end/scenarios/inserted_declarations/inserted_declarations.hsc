package inserted_declarations

import compiler from "base"
import testing from "std"

/*
 * #insert at the top level, among fields, variants and members, and among a match's patterns and a switch's
 * cases (docs/compilation.md, Code Values).
 */

// Declarations, one of which inserts code of its own
declarations :: fn() -> compiler.Code {
    return #code {
        ANSWER :: 30
        add_two :: fn(x: int) -> int {
            return x + #insert two()
        }
    }
}

two :: fn() -> compiler.Code {
    return #code(2)
}

#insert declarations()

position :: fn() -> compiler.Code {
    return #code fields {
        x : int,
        y : int = 2,
    }
}

shapes :: fn() -> compiler.Code {
    return #code variants {
        Circle(int),
        Empty,
    }
}

colors :: fn() -> compiler.Code {
    return #code members {
        Red,
        Green = 5,
    }
}

Point :: struct {
    #insert position(),
    z : int,
}

Shape :: union {
    Square(int),
    #insert shapes(),
}

Color :: enum {
    #insert colors(),
    Blue,
}

patterns :: fn() -> compiler.Code {
    return #code patterns {
        case .Red => 1
        case .Green => 2
    }
}

// A function whose match is quoted, with patterns spliced among its arms
classifier :: fn() -> compiler.Code {
    return #code {
        classify :: fn(color: Color) -> int {
            return match color {
                #insert patterns()
                case .Blue => 3
            }
        }
    }
}

#insert classifier()

cases :: fn() -> compiler.Code {
    return #code cases {
    case 1:
        n += 3
    case 2, 3:
        n += 100
    }
}

inserts_top_level_declarations #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, ANSWER, 30, "the inserted constant is a declaration of the package")
    testing.expect_eq(t, add_two(ANSWER), 32, "the inserted function adds the 2 its own #insert put in it")
    return .Ok
}

inserts_fields_variants_and_members #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    point := Point.{x = 1, z = 3}
    testing.expect_eq(t, point.x + point.y + point.z, 6, "the inserted fields are Point's, y with its default of 2")
    shape := Shape.Circle(4)
    radius := match shape {
        case Circle(r) => r
        case _ => 0
    }
    testing.expect_eq(t, radius, 4, "the inserted Circle variant holds its value")
    testing.expect_eq(t, cast[int](Color.Blue), 6, "Blue follows the inserted Green = 5")
    return .Ok
}

inserts_patterns_and_cases #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    color := Color.Green
    picked := match color {
        #insert patterns()
        case .Blue => 50
    }
    testing.expect_eq(t, picked, 2, "the inserted pattern for Green is among the match's arms")
    testing.expect_eq(t, classify(Color.Green), 2, "a quoted match takes inserted patterns too")
    testing.expect_eq(t, classify(Color.Blue), 3, "the quoted match's own arm follows the inserted ones")
    n := 5
    k := 1
    switch k {
    case 0:
        n += 50
    #insert cases()
    }
    testing.expect_eq(t, n, 8, "the inserted case 1 adds 3, and the case before it isn't taken")
    return .Ok
}

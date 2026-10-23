package inserted_declarations

import compiler from "base"

/*
 * #insert at the top level, among fields, variants and members, and among a match's patterns and a switch's
 * cases (docs/compilation.md, Code Values). main returns 42 if everything inserted did what it should.
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

main :: fn() -> int {
    // 30 + 2
    total := add_two(ANSWER)
    point := Point.{x = 1, z = 3}
    if point.x + point.y + point.z != 6 {
        return 1
    }
    shape := Shape.Circle(4)
    radius := match shape {
        case Circle(r) => r
        case _ => 0
    }
    if radius != 4 || cast[int](Color.Blue) != 6 {
        return 2
    }
    color := Color.Green
    // 2
    picked := match color {
        #insert patterns()
        case .Blue => 50
    }
    total += picked
    if classify(Color.Green) != 2 || classify(Color.Blue) != 3 {
        return 3
    }
    n := 5
    k := 1
    switch k {
    case 0:
        n += 50
    #insert cases()
    }
    // 32 + 2 + 8
    return total + n
}

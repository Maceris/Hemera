package match_not_exhaustive

Suit :: enum {
    Clubs,
    Hearts,
    Spades,
}

f :: fn(suit: Suit) -> int {
    return match suit {
        case .Clubs => 1
        case .Hearts => 2
    }
}

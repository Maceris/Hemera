package time

import runtime from "base"

now :: fn() -> Instant {
    //TODO(ches) fill this out
    return Instant.{0}
}

date :: fn(t: Instant) -> (year, month, day: int) {
    //TODO(ches) fill this out
    return 0, 0, 0
}

year :: fn(t: Instant) -> (year: int) {
    //TODO(ches) fill this out
    return 0
}

month :: fn(t: Instant) -> (month: int) {
    //TODO(ches) fill this out
    return 0
}

day :: fn(t: Instant) -> (day: int) {
    //TODO(ches) fill this out
    return 0
}

hour :: fn(t: Instant) -> (hour: int) {
    //TODO(ches) fill this out
    return 0
}

minute :: fn(t: Instant) -> (minute: int) {
    //TODO(ches) fill this out
    return 0
}

second :: fn(t: Instant) -> (second: int) {
    //TODO(ches) fill this out
    return 0
}

clock :: fn(t: Instant) -> (hour, minute, second: int) {
    //TODO(ches) fill this out
    return 0, 0, 0
}

precise_clock :: fn(t: Instant) -> (hour, minute, second, nanosecond: int) {
    //TODO(ches) fill this out
    return 0, 0, 0, 0
}


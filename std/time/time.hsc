package time

Time :: struct {
    nanoseconds: i64
}

now :: fn() -> Time {
    //TODO(ches) fill this out
    return Time.{0}
}

date :: fn(t: Time) -> (year, month, day: int) {
    //TODO(ches) fill this out
    return 0, 0, 0
}

year :: fn(t: Time) -> (year: int) {
    //TODO(ches) fill this out
    return 0
}

month :: fn(t: Time) -> (month: int) {
    //TODO(ches) fill this out
    return 0
}

day :: fn(t: Time) -> (day: int) {
    //TODO(ches) fill this out
    return 0
}

hour :: fn(t: Time) -> (hour: int) {
    //TODO(ches) fill this out
    return 0
}

minute :: fn(t: Time) -> (minute: int) {
    //TODO(ches) fill this out
    return 0
}

second :: fn(t: Time) -> (second: int) {
    //TODO(ches) fill this out
    return 0
}

clock :: fn(t: Time) -> (hour, minute, second: int) {
    //TODO(ches) fill this out
    return 0, 0, 0
}

precise_clock :: fn(t: Time) -> (hour, minute, second, nanosecond: int) {
    //TODO(ches) fill this out
    return 0, 0, 0, 0
}


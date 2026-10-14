package names_ok

import lib from "../names_ok_lib"

COUNT :: 4

Item :: struct {
    owner : ptr[Node],
    size : usize,
}

Shape :: union {
    Circle(Item),
    None,
}

Mode :: enum #backed_by(u8) {
    Fast,
    Slow = 5,
}

LIB_VALUE :: lib.VALUE

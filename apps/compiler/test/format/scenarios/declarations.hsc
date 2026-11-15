// D1: leading comments, then a blank line, then the package statement
package declarations
import text_buffer from "std:text_buffer"

// D2: imports sorted by location (base, std, user, vendor, relative), then path, then name
import vulkan from "vendor:vulkan"

import runtime from "base:runtime"
import strings from "std:strings"
import local from "../local"
import memory from "std:memory"
// L6: one blank line after the imports
// W7: a run of 4 or more constants lines up its ::
RED :: 0xff0000
GREEN :: 0x00ff00
BLUE :: 0x0000ff
TRANSPARENT_BLACK :: 0


// L6: at most one blank line in a row; a run of 3 isn't lined up
A :: 1
BB :: 2
CCC :: 3

// Both colons of NAME : Type : value line up
PAGE_SIZE : usize : 4096
CACHE_LINE : usize : 64
SECTOR : u32 : 512
WORD : u8 : 8

// A run breaks where lining up would pad a line more than 30 spaces
X :: 1
Y :: 2
Z :: 3
W :: 4
THIS_NAME_IS_FAR_LONGER_THAN_THE_OTHERS_IN_THE_RUN :: 5

// Struct fields line up their : and defaults' =
Window :: struct {
    title: string,
    width : u32 = 640,
    height : u32 = 480,
    fullscreen : bool = false,
}

Empty :: struct {}

// Enum members line up their =
Colour :: enum {
    RED = 1,
    GREEN = 2,
    BLUE = 4,
    ALPHA_CHANNEL = 8,
}

// W2: parameters are name : Type, like fields
area :: fn(width: u32, height: u32) -> u32 {
    return width * height
}

// A multiline string starts on the next line, 4 deeper
BANNER ::
\\first line
\\second line

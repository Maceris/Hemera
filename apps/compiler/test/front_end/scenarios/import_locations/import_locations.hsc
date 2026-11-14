package import_locations

// Each of these is an invalid location (E4042), so nothing is read for it
import io from "stb:io"
import escape from "std:../escape"
import nothing from "std:"
import doubled from "std:fake_io//deep"
import dotted from "std:fake_io."
import spaced from "std: fake_io"
import here from "std:./fake_io"
import backslash from "std:nested\deep"
import empty from ""

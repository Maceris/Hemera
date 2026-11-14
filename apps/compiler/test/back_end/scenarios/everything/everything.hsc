/*
 * Imports every package in std, so a build with --generate-all generates every function base and
 * std declare, used or not, for whichever target it's built for, with every generic instantiated by
 * generics_sweep. main does nothing else.
 */
package everything

import c_string from "std:c_string"
import generics_sweep from "../generics_sweep"
import concurrency from "std:concurrency"
import containers from "std:containers"
import fiber from "std:fiber"
import io from "std:io"
import logger from "std:logger"
import memory from "std:memory"
import os from "std:os"
import random from "std:random"
import reflection from "std:reflection"
import strings from "std:strings"
import text_buffer from "std:text_buffer"
import tiers from "std:tiers"
import time from "std:time"

main :: fn() -> int {
    return 42
}

/*
 * Imports every package in std, so a build with --generate-all generates every function base and
 * std declare, used or not, for whichever target it's built for, with every generic instantiated by
 * generics_sweep. main does nothing else.
 */
package everything

import c_string from "std"
import generics_sweep from "../generics_sweep"
import concurrency from "std"
import containers from "std"
import fiber from "std"
import io from "std"
import logger from "std"
import memory from "std"
import os from "std"
import random from "std"
import reflection from "std"
import strings from "std"
import text_buffer from "std"
import tiers from "std"
import time from "std"

main :: fn() -> int {
    return 42
}

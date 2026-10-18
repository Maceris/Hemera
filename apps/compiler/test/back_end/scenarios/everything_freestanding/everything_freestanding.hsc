/*
 * Imports every package in std, for a freestanding build with --generate-all: every function base
 * and std declare is generated with no operating system underneath, so the parts that need one
 * use their fallbacks (runtime/wait.hsc, os/unsupported.hsc). The entry does nothing.
 */
package everything_freestanding

import c_string from "std"
import generics_sweep from "../generics_sweep"
import concurrency from "std"
import containers from "std"
import fiber from "std"
import io from "std"
import logger from "std"
import memory from "std"
import os from "std"
import reflection from "std"
import strings from "std"
import text_buffer from "std"
import tiers from "std"
import time from "std"

kernel_entry #calling_convention(.c) #no_context :: fn() #never_returns {
    loop {}
}

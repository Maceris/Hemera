/*
 * Imports every package in std, for a freestanding build with --generate-all: every function base
 * and std declare is generated with no operating system underneath, so the parts that need one
 * use their fallbacks (runtime/wait.hsc, os/unsupported.hsc). The entry does nothing.
 */
package everything_freestanding

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

kernel_entry #calling_convention(.c) #no_context :: fn() #never_returns {
    loop {}
}

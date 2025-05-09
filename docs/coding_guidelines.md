# Coding Guidelines

## Functions

### Size

A function should do exactly 1 thing, with thing meaning one of the below (examples are provided).

1. Read/write/move an isolated unit of data, without transformation
    * Load a 3D model from disk into memory
    * Write an image to disk
    * Read a line of text from an input stream
    * Copy a block of memory from RAM to VRAM
    * Send an HTTP request
    * Send a document to a printer
2. Perform one operation with an effect outside the program
    * Turn on an LED
    * Delete a file
    * Create a kernel thread
    * Change memory protection for a memory page
3. Perform one transformation on a unit of data
    * Parse input into a struct
    * Transform text to uppercase
    * Format a string
    * Convert a struct to/from a JSON string
    * Convert an image to another format/encoding
    * Find the shortest path between two points on a graph
    * Validate a set of data
4. Decide on which task(s) to perform
    * Select the right event handler for an event
    * Call the appropriate function based on a value
    * Dispatch a virtual call (or similar) to the right function

They should not do 2 or more tasks, such as:

* Read command line arguments and also parse them into a struct
* Map one data structure to another, while validating it is correct
* Handle the logic for both the formatting of a string and the physical writing of the result an output stream

Additionally, they should not do less than the entire task, or be broken up into smaller functions, unless at least one of the following is true:

* The sub-function is frequently (more than twice) reused
* The sub-function needs to remain consistent across multiple (more than one) usages

There is no size limitation or recommendation for functions, file size limitations aside.
A function may be a single line, or well over a thousand, it is whatever size it needs to be to do the one task.


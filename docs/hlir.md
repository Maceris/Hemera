# HLIR (High Level Intermediate Representation)

The High Level Intermediate Representation is the first stage that Hemera source code is compiled down to.
It is also the type of code that is executed during compile time execution.

## Values

The values in the program are largely based on LLVM, though more constrained and designed for our specific needs.

* Value
    * Argument
    * Basic Block
    * User
        * Constant
            * Integer
            * Floating Point
        * Instruction
            * Binary
            * Branch
            * Call Base
                * Call
                * Call Branch
            * Return
            * Unary


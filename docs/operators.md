# Operators

Operators combine operands into expressions. For binary operations, the operand types must either be identical or implicitly convertible, unless the operand involves shifts or untyped constants.

## Address operators

For an operand `x` of type `T`, the address operation `&x` will generate a pointer `ptr<T>` to `x`.

For an operand `x` of type `ptr<T>`, the dereference operation `x^` will result in the variable of type `T` pointed to by `x`. If x is an invalid address, such as `null`, dereferencing the pointer will result in platform specific behavior, likely a segmentation fault.

```
x : int = 1
y : ptr<int> = &x
z : int = y^

y = null
y^ // segfaults, probably
```

## Arithmetic operators

Unary:
```
+                      +x is equivalent to 0 + x
-  negation            -x is equivalent to 0 - x
~  bitwise complement  ~x is equivalent to m ~ x where m is "all bits set to 1" for unsigned x
                                                 and m = -1 for signed x
```

Binary:
```
+   addition                 integers, enums, floats, complex values, quaternions, vectors, matrices, constant strings
-   subtraction              integers, enums, floats, complex values, quaternions, vectors, matrices
*   multiplication           integers, floats, complex values, quaternions, vectors, matrices
/   division                 integers, floats, complex values, quaternions, vectors
%   modulus (truncated)      integers
%%  remainder (floored)      integers

&   bitwise AND              integers, enums
|   bitwise OR               integers, enums
~   bitwise XOR              integers, enums
<<  left shift               integer << integer >= 0
>>  right shift (arithmetic) integer >> integer >= 0
>>> right shift (logical)    signed integer >>> integer >= 0
```

Except for shift operations, if one operand is an untyped constant
and the other operand is not, the constant is implicitly converted to
the type of the other operand (if possible).

In a shift expression, the right operand must have an unsigned integer type
or be an untyped constant that will be implicitly converted to
an unsigned integer.

If the left operand of a non-constant shift expression is an
untyped constant, it is first implicitly converted to the type it would
assume if the shift expression were replaced by the left operand alone.

Normal right-shifts (`>>`) for signed integers will fill displaced bits with the current sign bit.
In order to have signed integers always fill the displaced bits with 0 when shifting right, the
`>>>` operator must be used.

## Assignment operators

```
=    assignment                a = b assigns a to the value of b
+=   addition                  a += b is a = a + b
-=   subtraction               a -= b is a = a - b
*=   multiplication            a *= b is a = a * b
/=   division                  a /= b is a = a / b
%=   modulus (truncated)       a %= b is a = a % b
%%=  remainder (floored)       a %%= b is a = a %% b

&=   bitwise AND               a &= b is a = a & b
|=   bitwise OR                a |= b is a = a | b
~=   bitwise XOR               a ~= b is a = a ~ b
<<=  left shift                a <<= b is a = a << b
>>=  right shift (arithmetic)  a >>= b is a = a >> b
>>>= right shift(logical)      a >>>= b is a = a >>> b

&&=  logical AND               a &&= b is a = a && b
||=  logical OR                a ||= b is a = a || b
```

## Comparison operators

```
== equal
!= not equal
>  greater than
>= greater than or equal to
<  less than
<= less than or equal to
```

## Function operators
```
|> pipe operator for function chaining
?  try operator
```

### Pipe operator
The pipe operator takes output from one function and provides it as input for another.

By default it will provide all output, in order, at the start of the next functions arguments.

```
get_string :: fn() -> string {/* ... */}
uppercase  :: fn(a: string) -> string {/* ... */}
append     :: fn(a: string, b: string) -> string {/* ... */}

example :: fn() {
    get_string()
    |> uppercase() // Provided the output from get_string()
    |> append("Second argument")
}
```

Any additional arguments to functions must be provided explicitly if it has more arguments than will be supplied
by the previous function.

If any arguments are explicitly provided, they are considered to come after any inputs from the previous function.
Additionally, all arguments from the previous function must be used.

```
get_1_string  :: fn() -> string {/* ... */}
get_2_strings :: fn() -> string, string {/* ... */}
append     :: fn(a: string, b: string) -> string {/* ... */}

example :: fn() {
    get_1_string()
    |> append() // Error: needs a second argument

    get_1_string()
    |> append("2nd arg") // Fine

    get_2_strings()
    |> append()          // Fine

    get_2_strings()
    |> append("Last argument?") // Error: too many arguments (attempting to provide 3)
}
```

In order to specify a more complex pattern or use fewer results, the "_" placeholders can be used to indicate positions to fill.
These placeholders will be filled out using the results of the previous function, in order. Anything not used will be ignored.
If there are N placeholders, there must be at least N results from the previous function to use or it is an error.

```
foo :: fn() -> int, bool, string {/* ... */}
bar :: fn(a: int, b: string, c: bool) {/* ... */}

example :: fn() {
    foo()
    |> bar(_, "Example", _)      // Provided only the first 2 outputs

    foo()
    |> bar(_, "Example", false)  // Provided only the first output

    foo()
    |> bar($1, "Example", false) // Equivalent to the previous example
}
```

Should more granular control over the ordering or usage be required, outputs are referred by number with a $ prefix.
`$1` would be the first return value from the previous function, `$2` the second, and so on.

```
foo :: fn() -> int, bool {/* ... */}
bar :: fn(a: int, b: bool) -> int, bool, string {/* ... */}
baz :: fn(a: bool, b: string, c: int) -> string {/* ... */}

example :: fn() {
    result: string = foo()
    |> bar()                  // Passed two arguments
    |> baz($2, "Example", $1) // Reorders output, ignores third result
}
```
### Try operator (subject to change)

[//]: # (TODO are we removing this in favor of a macro?)

In functions that 

* Return a `Result<T1, E>` which call another function that returns a `Result<T2, E>` where the `E` types match (`T1` and `T2` may or may not)
* Return a `Option<T>` which call a function that returns an `Option<T>` where the `T` types match

the try operator (`?`) can be appended to propagate error values up.

```
foo :: fn() -> Result<i32, ExampleError> {
    example1 : f32 = bar()?
    
    // The above is equivalent to something like this
    example2 : f32 = match bar() {
        Ok(value) => value,
        Error(e) => return Error(e),
    }
    // ...
}

bar :: fn() -> Result<f32, ExampleError> {
    // ...
}
```

Or, for options

```
foo :: fn() -> Option<i32> {
    example1 : f32 = bar()?
    
    // The above is equivalent to something like this
    example2 : f32 = match bar() {
        Some(value) => value,
        None() => return None(),
    }
    // ...
}

bar :: fn() -> Option<f32> {
    // ...
}
```

## Logical operators

```
&&  logical AND
||  logical OR
!   logical NOT
```

## Ternary Operators

## Other operators


# Operator Details

## Operator precedence

## Integer operators

## Integer overflow

## Floating-point operators


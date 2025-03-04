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
y^ // segfaults
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
+   addition        integers, enums, floats, complex values, quaternions, vectors, matrices, constant strings
-   subtraction     integers, enums, floats, complex values, quaternions, vectors, matrices
*   multiplication  integers, floats, complex values, quaternions, vectors, matrices
/   division        integers, floats, complex values, quaternions, vectors
%   modulus         integers

|   bitwise OR      integers, enums
&   bitwise AND     integers, enums
~   bitwise XOR     integers, enums
>>  right shift     integer >> integer >= 0
<<  left shift      integer << integer >= 0
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

## Assignment operators

## Comparison operators

## Function operators
```
|> pipe operator for function chaining

```

The pipe operator takes output from one function and provides it as input for another.

By default it will provide all output, in order, at the start of the next functions arguments. Additional arguments will have to be provided.

```
get_string :: fn() -> string {/* ... */}
uppercase  :: fn(a: string) -> string {/* ... */}
append     :: fn(a: string, b: string) -> string {/* ... */}

example :: fn() {
    get_string()
    |> uppercase() // Provided the output from get_string()
    |> append("This is the second argument")
}
```

If you are fine with the order, but want to specify a more complex pattern, you can use "_" placeholders. Anything not used will be ignored.

```
foo :: fn() -> int, bool, string {/* ... */}
bar :: fn(a: int, b: string, c: bool) {/* ... */}

example :: fn() {
    foo()
    |> bar(_, "Example", _) // Provided only the first 2 outputs
}
```

Should you need more granular control over the ordering or usage, you will need to refer to them by number with a $ prefix. `$1` would be the first return value from the previous function, `$2` the second, and so on.

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

## Logical operators

## Ternary Operators

## Other operators


# Operator Details

## Operator precedence

## Integer operators

## Integer overflow

## Floating-point operators


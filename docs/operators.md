# Operators

Operators combine operands into expressions. For binary operations, the operand types must either be identical or implicitly convertible, unless the operand involves shifts or untyped constants.

## Address operators

For an operand `x` of type `T`, the address operation `&x` will generate a pointer `ptr[T]` to `x`.

For an operand `x` of type `ptr[T]`, the dereference operation `x^` will result in the variable of type `T` pointed to by `x`. If x is an invalid address, such as `null`, dereferencing the pointer will result in platform specific behavior, likely a segmentation fault.

```
x : int = 1
y : ptr[int] = &x
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

For two integers `x` and `y`, the integer quotient `q = x/y` (truncated towards zero) and modulus 
`m = x%y` satisfies the following relationship

```
x = q * y + m    and |q| < |y|
``` 

For two integers `x` and `y`, the integer quotient `q = x/y` and remainder `r = x %% y` satisfies the following relationship:

```
r = x - y * floor(x / y)
```

The exception is when `x` is the largest non-negative value, and the quotient `q = x/-1` is equal to `x` due to 
two's complement integer overflow.

The divisor for division, modulus, and remainder must not be zero if constant. If zero at runtime, there will be a runtime panic.

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
>>>= right shift (logical)     a >>>= b is a = a >>> b

&&=  logical AND               a &&= b is a = a && b
||=  logical OR                a ||= b is a = a || b
```

Multiple values can be assigned in one expression, for example `a, b, c = 1` will set all of the values to 1, and `a, b = b, a` will swap the 2 values. 

These evaluate independently/concurrently, as explained in this example:

```
x : int = 2
y : int = 3

x, y += y, x
// both values are 5 here.
// It does NOT do x += y and then y += x, which would give x = 5 and y = 8
```

If there are multiple values being assigned, the number of values on the right must either be equal to the number on the left, or 1. For example,
`a = b, c` is NOT valid, but `a, b = c` and `a, b = c, d` are valid.

Functions that return multiple values count as that number of values.
Things like `a, b, c = get_two_values(), 3` are fine.

Assignment operators can be chained, and will be evaluated from right to left.

Here is an somewhat unhinged example:

```
x : int = 3
y : int = 2
z : int = 1

x, y = y, x = z, y
// Assigns y to z(which is 1), and x to y(which is 2)
// Then swaps x and y, so here x = 1 and y = 2

x, y <<= y, x += 3 * 1 - 1
// Adds 2 to both x and y, so x = 3 and y = 4
// Then shifts x(3) left by y(4), and y(4) left by x(3)
// So here x = 48 and y = 32.

// I'm begging you to not write code like this
// The compiler will satisfy your dark desires but I am not happy about it
```

As an expression, the result is considered to be the final value after
being assigned to the left-most side.

## Casting operators

```
cast[T](value)      converts a value to a compatible type T
bit_cast[T](value)  does a bit cast conversion from value to type T of the same size
auto_cast(value)    automatically converts the value to the necessary type, if possible
```

Note that `auto_cast` is intended for prototypes, and generally discouraged. But we aren't the casting police.

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
get_2_strings :: fn() -> (string, string) {/* ... */}
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
foo :: fn() -> (int, bool, string) {/* ... */}
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
foo :: fn() -> (int, bool) {/* ... */}
bar :: fn(a: int, b: bool) -> (int, bool, string) {/* ... */}
baz :: fn(a: bool, b: string, c: int) -> string {/* ... */}

example :: fn() {
    result: string = foo()
    |> bar()                  // Passed two arguments
    |> baz($2, "Example", $1) // Reorders output, ignores third result
}
```

## Logical operators

```
&&  logical AND
||  logical OR
!   logical NOT
```

## Optional operators

There are built in operators for optional types (`T?`).

```
is_none      a is_none      evaluates to false if the optional does not have a value, or false if it does
is_some      a is_some      evaluates to true if the optional value a is some value, or false if it is not
or_break     a or_break     breaks if an optional is not present, otherwise evaluates to the value
or_continue  a or_continue  continues if an optional is not present, otherwise evaluates to the value
?            a?             evaluates to an optionals value if present, or returns an empty optional if not
or_else      a or_else b    evaluates to an optionals value if present, or the provided default if not
or_return    a or_return b  evaluates to an optionals value if present, or returns a default value if not
```

Some examples of usage:
```
example :: fn() -> i32 {
    foo : i32? = some_function()
    
    if foo is_some {
        println("Foo exists")
    }

    if foo is_none {
        println("This should have been an else")
    }
    
    // Will be the value of foo if the value is present, or 5 if not
    bar : i32 = foo or_else 5

    // Will result in the value of foo if there is one, or return 10 immediately if not
    baz :: foo or_return 10

    //...
}

example_2 :: fn() {
    option : i32? : some_function()
    
    // If a function does not have a return value, void is used (like a normal return would have)
    bar :: option or_return void
    //...

    loop {
        if some_function() or_continue == 3 {
            println("These can be used in expressions")
        }

        foo : ExampleType : another_function() or_break

        // ...
    }
}
```

## Other operators

```
..   for use in defining resizable arrays, and creating array views
..=  inclusive range
..<  half-open range
```

## Result operators

There are built in operators for result types.

```
or_break     a or_break     breaks if the result is an error, otherwise evaluates to the value
or_continue  a or_continue  continues if the result is an error, otherwise evaluates to the value
?            a?             evaluates to the Ok value if present, or returns the error value if not
or_else      a or_else b    evaluates to the Ok value if present, or the provided default if it was an error
or_return    a or_return b  evaluates to the Ok value if present, or returns a default value if was an error
```

```
MyError :: enum {
    OutOfCheese,
    BreadBurnt,
    TooManyWasps,
}

f1 :: fn() -> Result[bool, MyError] {
    //... return a bool or error
}

f2 :: fn() -> Result[string, MyError] {
    result : bool : f1()? // could return here
    if result {
        return .Ok("test")
    }
    return .Ok("value")
}
```

# Operator Details

## Operator precedence

```
Precedence   Operator
    11       cast  auto_cast  bit_cast  |>  .  []
    10       +  -  ~  !  ?  (unary versions)
     9       ()
     8       *  /  %  %%  &  <<  >>  >>>
     7       +  -  |  ~
     6       ==  !=  <  >  <=  >=
     5       &&
     4       ||
     3       ..=  ..<
     2       if  is_none  is_some  or_break  or_continue  or_else  or_return
     1       = += &&= &= |= ~= /= <<= %= *= ||= %%= >>= >>>= -=
```

Unary operators have the highest precedence.

Binary operators of the same precedence are evaluated left to right.
For example, `a / b * c` is evaluated as `(a / b) * c`.

## Integer overflow

For unsigned integers, the operators `+`, `-`, `*`, and `<<` are computed modulo 2^n, where n is the 
bit width of the unsigned integer's type. This means that the high bit are discarded upon overflow, 
and integer values will wrap around.

For signed integers, the operators `+`, `-`, `*`, `/`, and `<<` are computed as determined by the
two`s compliment binary representation of the integer value. Overflow will not cause a runtime panic.
For example, `x < x + 1` cannot be assumed to always be true.

## Floating-point operators

For floating-point, complex, quaternion, or other floating-point embedded types:

* `+x` is the same as `x`
* `-x` is the negation of `x`

Division by zero on floating point operates as defined in IEEE-754, a runtime panic may occur.

Implementations may use fused operations that combine multiple floating-point operations into a single one,
even if that produces a different result from the value obtained from individually executing and 
rounding results from instructions.

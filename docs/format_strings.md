# Format Strings

Logging, printing and building text take a format string and values to put in it:

```
runtime.log_info("% of % pages free", free, total)
text_buffer.append_format(&text, "loaded % in %{.2} ms", name, elapsed)
message :: strings.format("%{>8} | %{08x}", label, address) or_return
```

Each `%` is replaced by the next value. `%1`, `%2` and so on are the first, second... value instead, without moving on to
the next, so a value can be used twice or out of order: `"%2 before %1"`. `%%` is a `%`.

Every formatter reads them the same way: base's `runtime.output_format` (the standard logger and assertion handler use
it), std's `text_buffer.append_format` (and `strings.format`, the loggers and printing, which use it), and the compiler,
for compile-time logging and `compiler.require`'s messages (see [types.md](types.md#constraints)).

## Values

| Value | Written as |
|---|---|
| Integers | Decimal |
| Floats | Six decimals, rounded: `2.500000` (std and compile time only) |
| Booleans, characters, strings | As they are: `true`, `x`, `text` |
| Enum members | By name: `GREEN`, or `Color(7)` for a value that isn't a member |
| Pointers and functions | Their address in hexadecimal, `0x...`, or `null` |
| Structs, arrays, unions | Their fields and elements, like `Point{x = 1, y = 2}` (std and compile time; base writes `<struct Point>`) |
| Types | By name |

## Options

A placeholder can have options in braces right after it: `%{08x}`, `%2{>10}`. A `%` followed by anything else is a
placeholder followed by that text, as it always was.

```
%[n]{[[fill]align][+][#][0][width][.precision][kind]}
```

| Option | Means |
|---|---|
| `width` | At least this many characters, padded |
| `align` | `<` left, `>` right, `^` centered. Without one, numbers go to the right and everything else to the left |
| `fill` | The character to pad with, before the alignment, like `*` in `%{*>8}`. A space by default |
| `0` | Pads a number with zeros after its sign and prefix: `%{05}` gives `-0042` |
| `+` | A sign on numbers either way: `+7` |
| `#` | A prefix for the kind: `0x`, `0b` or `0o` |
| `.precision` | A float's decimals, or how much of a string to keep |
| `kind` | `d` decimal, `x` or `X` hexadecimal, `b` binary, `o` octal: for integers, and for characters, booleans, enum members and pointers as their numbers |

```
"kernel+%{#x}" with 0x1f40       kernel+0x1f40
"%{08x}" with 0x1f40             00001f40
"[%{>6}]" with 42                [    42]
"[%{^6}]" with 42                [  42  ]
"[%{*>5}]" with 42               [***42]
"%{#b}" with 5                   0b101
"%{.3}" with 3.14159             3.142
"[%{.3}]" with "hello"           [hel]
"%2{x} %1" with 10, 255          ff 10
"%{d}" with Color.GREEN          1
```

A pointer with options and no kind is written in hexadecimal with `0x`, as it is without them, so `%{>20}` right-aligns
an address.

## Checking

A format string written in place, for a parameter named `format_string` followed by `any...` values (`log_info`'s,
`append_format`'s, `strings.format`'s, and any function written the same way), is checked where it's used. Each of
these is an error (E4034):

* A placeholder without a value: `log_info("% and %", one)`
* `%0`, since values are numbered from `%1`
* Options that aren't well formed: `%{08q}`
* Options the value's type can't take: a kind for something that isn't a number, like `%{x}` for a string; `+` or `0`
  for something that isn't a number; `#` without `x`, `X`, `b` or `o`; or a precision for something other than a
  float or a string

A format string that isn't written in place, or values passed on as a view (`log_info(format_string, values)`), are
only known when the program runs: there, a placeholder without a value, or with options that aren't well formed, is
written as `%!`. Values left over are ignored.

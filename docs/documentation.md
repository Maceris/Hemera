# Documentation Comments

A declaration is documented by a comment in Doxygen's style: `/** ... */` directly before it. The compiler keeps these
comments, checks them against what they document, and gives them to compile-time code through reflection, so tools
like a build's checks, a program's help, or a generator of reference pages read the same documentation the source has.

```
/**
 * Copy files into a directory, each keeping its name.
 *
 * Files are copied in the order the set gives them, each whole before the next starts, so a copy that stops leaves
 * every file before it complete and none after it begun.
 *
 * @param from The files to copy. Directories in the set are skipped, not copied into.
 * @param into The directory they go in, which has to exist already; it isn't made.
 * @param force Whether a file of the same name in into is replaced. If false, such a file is left alone, and the
 *     copy stops there with Exists.
 * @return The number of files copied, from 0 when the set is empty to the set's count.
 * @error NoSpace The volume filled; the file being copied is removed, so no partial file is left.
 * @error Exists A file of the same name was there, and force was false.
 * @example copy(notes, backup, false)
 */
copy :: fn(from: FileSet, into: Dir, force: bool) -> Result[int, CopyError] {
    ...
}

CopyError :: enum {
    /** The volume filled. */
    NoSpace,
    Exists, /**< A file of the same name was in the way. */
}
```

Every other comment, `//` and `/* ... */`, is a plain comment, which documents nothing and which the compiler drops.

## Where They Go

- `/** ... */` documents the declaration that starts right after it: a package (before `package`), a function, a type,
  a constant, an alias, a struct's field, an enum's member, or a union's variant. Plain comments may come between them.
- `/**< ... */` documents what's before it on its line: a field, a member or a variant, after it on the same line.
- A comment that starts with three stars (`/***`) or is empty (`/**/`) is a plain comment.

## What's in One

- **The summary**: the first sentence of the comment's first paragraph, up to a full stop followed by a space or the
  line's end, or the whole paragraph without one; or what `@brief` says, if there is one.
- **The details**: the rest of the text before the tags, paragraphs separated by blank lines.
- **Tags**, each at the start of a line, its text running to the next tag or the comment's end:

| Tag | Documents |
| --- | --- |
| `@brief text` | The summary, in place of the first sentence |
| `@param name text` | A parameter |
| `@tparam name text` | A generic parameter |
| `@return text` (or `@returns`) | What it returns; one for each of several results, in order |
| `@error name text` | One of the errors it returns: a variant of its `Result`'s error type |
| `@note text` | Something to know |
| `@see text` | Something related |
| `@example text` | An example, its lines kept as they're written |
| `@deprecated text` | That it shouldn't be used, and what to use instead |
| `@since text` | When it was added |

Each line of a comment loses its margin: the spaces at its start, then a `*` and one space after it, as above.

A function with several results has an `@return` for each, in order. When they're named, each one's text starts with
its name; when they aren't, the first `@return` is the first result's, and so on:

```
/**
 * Read bytes from a file into a buffer.
 *
 * @param file The file, read from where the last read ended.
 * @param buffer Where the bytes go; at most its count are read.
 * @return count How many bytes were read: 0 only at the file's end, and fewer than the buffer holds when less is left.
 * @return error Why reading stopped early, or null if it didn't.
 */
read :: fn(file: File, buffer: mut u8[]) -> (count : usize, error : FileError?)
```

## Writing Them

Documentation states a declaration's contract: what a caller can rely on, and what it has to provide. A name and a
type already say what something is called and how it's stored; documentation says what neither does.

- **Every parameter, every result.** Each gets its tag, even when the function is simple. A parameter isn't left out
  because its name seems to say it all; when unsure, say more.
- **Never restate the name.** `@param x The x value.` says nothing. Say what a caller needs: its units (bytes,
  nanoseconds, pixels), its valid values and ranges (can it be zero or negative? is there a largest?), why it's the type
  it is when that isn't obvious (why an integer, not a float), what null or an optional's `None` means, who owns memory
  passed in or out and how long a view stays good, and what happens at the edges.
- **Results say what can come back**, and when: each value's range, when it's null or empty, and each error with what
  it means for the caller and what state it leaves behind.
- **The summary is a verb phrase**, a sentence that ends in a full stop: "Copy files into a directory." It's what a
  list of functions shows, so it stands alone. `@brief` is only for when the first sentence can't be the summary.
- **Tag text is sentences**, starting with a capital and ending with a full stop.
- **Fields, members and variants** are documented as parameters are: units, valid values, and what each one means.

## What's Checked

These are compile errors (E3034 for a malformed comment, E4041 for one that doesn't match its declaration):

- A tag that isn't one of the above.
- `@param`, `@tparam` or `@error` without a name.
- A tag given twice: the same `@param`, `@tparam` or `@error` name, a named result's `@return`, or `@brief`,
  `@deprecated` or `@since`.
- `/** */` with nothing declared after it, or two of them before one declaration.
- `@param` naming no parameter, or `@tparam` no generic parameter.
- More `@return`s than the function has results, or, when its results are named, one that doesn't start with one of
  their names.
- `@error` on a function that doesn't return a `Result`, or naming no variant of its error type when that's an enum or
  a union. A function's errors are checked with its body, so a function without one isn't.

`--no-documentation-checks` turns them off; given to a build, it turns them off for every target the build builds.

What isn't checked is what's missing: a function without documentation, or one that leaves a parameter out. A build
can check for that through reflection (below), with the rules it chooses.

## Reading Them

Compile-time code reads a function's documentation in `compiler.FunctionInfo`, from `find_function`:
`documentation`, a `compiler.Documentation` of `brief`, `details` and `tags` (each a `compiler.DocumentationTag` of
`tag`, `name` and `text`), each of its `parameters`' `documentation`, its `@param`'s text, and each of its
`return_values`' `documentation`, its `@return`'s text without the result's name. A package's
`constants` each have their `documentation` too, and its `types` theirs, with `members`: each field's, enum member's or
union variant's that's documented, by its name. What has no documentation comment has them all empty.

```
info :: compiler.package_info("files") or_else compiler.PackageInfo.{}
copy :: compiler.find_function(&info, "copy") or_else compiler.FunctionInfo.{}
summary :: copy.documentation.brief
```

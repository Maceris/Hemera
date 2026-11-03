# Documentation Comments

A declaration is documented by a comment in Doxygen's style: `/** ... */` directly before it. The compiler keeps these
comments, checks them against what they document, and gives them to compile-time code through reflection, so tools
like a build's checks, a program's help, or a generator of reference pages read the same documentation the source has.

```
/**
 * Copies files into a directory. Each one keeps its name.
 *
 * Nothing that's there already is replaced, unless asked.
 *
 * @param from the files to copy
 * @param into where they go
 * @param force replace what's there
 * @return how many were copied
 * @error NoSpace the volume filled; nothing after it was copied
 * @example copy notes backup
 */
copy :: fn(from: FileSet, into: Dir, force: bool) -> Result[int, CopyError] {
    ...
}

CopyError :: enum {
    /** The volume filled. */
    NoSpace,
    Missing, /**< Nothing was at the path. */
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
| `@return text` (or `@returns`) | What it returns |
| `@error name text` | One of the errors it returns: a variant of its `Result`'s error type |
| `@note text` | Something to know |
| `@see text` | Something related |
| `@example text` | An example, its lines kept as they're written |
| `@deprecated text` | That it shouldn't be used, and what to use instead |
| `@since text` | When it was added |

Each line of a comment loses its margin: the spaces at its start, then a `*` and one space after it, as above.

## What's Checked

These are compile errors (E3034 for a malformed comment, E4041 for one that doesn't match its declaration):

- A tag that isn't one of the above.
- `@param`, `@tparam` or `@error` without a name.
- A tag given twice: the same `@param`, `@tparam` or `@error` name, or `@brief`, `@return`, `@deprecated` or `@since`.
- `/** */` with nothing declared after it, or two of them before one declaration.
- `@param` naming no parameter, or `@tparam` no generic parameter.
- `@error` on a function that doesn't return a `Result`, or naming no variant of its error type when that's an enum or
  a union. A function's errors are checked with its body, so a function without one isn't.

`--no-documentation-checks` turns them off; given to a build, it turns them off for every target the build builds.

What isn't checked is what's missing: a function without documentation, or one that leaves a parameter out. A build
can check for that through reflection (below), with the rules it chooses.

## Reading Them

Compile-time code reads a function's documentation in `compiler.FunctionInfo`, from `find_function`:
`documentation`, a `compiler.Documentation` of `brief`, `details` and `tags` (each a `compiler.DocumentationTag` of
`tag`, `name` and `text`), and each of its `parameters`' `documentation`, its `@param`'s text. A package's
`constants` each have their `documentation` too, and its `types` theirs, with `members`: each field's, enum member's or
union variant's that's documented, by its name. What has no documentation comment has them all empty.

```
info :: compiler.package_info("files") or_else compiler.PackageInfo.{}
copy :: compiler.find_function(&info, "copy") or_else compiler.FunctionInfo.{}
summary :: copy.documentation.brief
```

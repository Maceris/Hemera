# Editor Support

`hemera-lsp` is Hemera's language server. An editor starts it and speaks the
[Language Server Protocol](https://microsoft.github.io/language-server-protocol/) to it over standard input and output,
and it shows the compiler's errors and warnings where they are, each time a file is opened or saved, formats,
outlines and folds files, finds what names refer to, and colors each by what it is, with signature help and inlay
hints. The VS Code extension is built with it; another editor with a
language server client can start `hemera-lsp` the same way.

## Building

Both are built with the compiler, from the repository's root, once it's configured (`cmake --preset windows`, as the
README says):

```
cmake --build build/windows --config Release --target HemeraLsp HemeraVscode
```

* `HemeraLsp` builds `hemera-lsp`, beside `hemera` in `build/<preset>/bin/<configuration>`. A Debug build is
  `hemera-lsp-debug`.
* `HemeraVscode` packages the VS Code extension as `hemera.vsix`, in the same folder. It needs Node.js and npm, and
  fetches its packages with `npm ci`, so it's only built when it's named. Without npm, there's no such target.

## VS Code

The extension isn't on the Marketplace. Install it from the file:

```
code --install-extension build/windows/bin/Release/hemera.vsix
```

It gives `.hsc` files Hemera's syntax highlighting, brackets and comments, and starts `hemera-lsp` for them. Put
`hemera-lsp` and `hemera` on the `PATH`, or set where they are:

| Setting | What it is |
|---|---|
| `hemera.serverPath` | The language server, `hemera-lsp` by default: a path, or a name looked for on the `PATH`. |
| `hemera.compilerPath` | The compiler, `hemera` by default, the same way. |
| `hemera.root` | The package checked for a file in the workspace, like a build package's folder: relative to the first workspace folder, or absolute. Empty, the default, checks each file's own folder. |
| `hemera.arguments` | More of the compiler's flags for each check, like `--setting=name=value` for a build package's settings. |
| `hemera.checkerMemory` | The most memory, in MB, the long-lived checker may use before it's started again: 8192 by default, 0 for no limit. |

A change to `hemera.serverPath` restarts the server; the others apply from the next check.

## What's Checked, and When

Opening or saving a `.hsc` file checks the package it belongs to: `hemera.root` for a file in the workspace when it's
set, otherwise the file's own folder, as a program. The check is
[`hemera --check --diagnostics=json`](compilation.md#checking-without-building), so compile-time code runs as it would
in a build, a build package's checks included, and nothing is written but what that code writes itself.

* **Unsaved changes** in every open file are checked as they are: each goes to the compiler through `--overlay`. A file
  that's never been saved isn't seen, as packages are found by listing their folders.
* **Diagnostics** are shown in each file they're in, open or not, once each, though a file can be in several of a build
  package's targets. One reaches from where the compiler puts it to the end of the word or string there. A file that
  had diagnostics and has none after a check is cleared.
* **Codes** are shown as the compiler prints them, like `hemera:E4015`, so they can be searched for (see
  [Diagnostics](compilation.md#diagnostics)). Errors, warnings and what compile-time code logs below the warning level
  are shown as errors, warnings and information.

In a build package, the first file opened checks every target, which can take tens of seconds. After that, saving a
file checks just the targets that read it, which the [name index](compilation.md#the-name-index) says, as no other
target's diagnostics or index can change. What those targets find replaces what they found before, and what the other
targets found stays. A file no target read yet, like a new one, is checked as the other files in its folder are; one
in a folder no target read is a check of everything.

An open file that no target reads even then, like one only another architecture's targets import, isn't checked, and
its names lead nowhere: it says so, as information on its package statement. A setting that adds the targets that
read it, given in `hemera.arguments` like `--setting=name=value`, checks those instead.

Every check goes to a compiler the server keeps running, [`hemera --serve`](compilation.md#a-long-lived-compiler),
which keeps the build package's own check from one to the next, so a save's diagnostics take about as long as
checking its targets: a second or two for a target or two. It starts again when it's asked to, or uses more memory
than `hemera.checkerMemory`. A save that changes the build package itself checks every target, as its targets, or
how they're made, may have changed. An error in a package the build package loads, to read its constants, stops the
build before its targets, as it would in a build: the error is shown in place of what the checked targets found, and
the index stays as it was until it's fixed.

* **Hemera: Check Everything**, in the command palette, checks every target of each open file's package, for what a
  change outside the editor, like a file deleted or changed by another program, may have changed.
* **A check of some targets** waits for a check of other targets that's running, and a check of everything for any
  check, so each one's diagnostics are shown. A newer check of the same targets stops the older one.

Checking as you type isn't done: a large build package can take tens of seconds to check in full, so checks come with
opening and saving.

A change to the settings clears every diagnostic shown and checks the open files again, so a file checked through
another root doesn't keep what that root found.

## Formatting, the Outline and Folding

These come from the server's own lexer and parser, in its own process, as you type, without the compiler's check:

* **Format Document** lays a file out as [`hemera-format`](formatting.md) does, changing only what has to change, so
  the cursor and what's folded outside it stay where they are. A file that doesn't parse is left as it is. The editor's
  tab size and spaces settings don't apply, as the layout is fixed; to format on save, turn on VS Code's
  `editor.formatOnSave` for Hemera.
* **The outline** lists a file's declarations: functions, structs, enums, unions, aliases and constants, with a
  struct's fields, an enum's members and a union's variants under them. A declaration with a syntax error is still
  there, as far as it was written, and so are those after it. While a file doesn't lex, like with a string left open,
  it shows the last version that did.
* **Folding** folds blocks, brackets over several lines, block comments, runs of line comments, and runs of imports,
  whether the file parses or not.

There's no range formatting, as a part of a file's layout depends on what's around it.

## Completion

Completion comes as you type, and after a `.`, from the last check's [name index](compilation.md#the-name-index) and
the file as it is now, without a check, so it's there once a file's package has been checked:

* **After a `.`:** a package's declarations after an import's name; an enum's members after its name; a value's
  fields, following each `.` before it through the fields' types, through pointers, and through what a call's function
  gives, like `shapes.moved(p).x`. A name typed since the check is found by name: a local declared before it, an
  import, or the package's own declaration.
* **A name:** the locals declared before it in the same declaration, those typed since the check included, the
  package's declarations in every file, the file's imports, the builtin types and the keywords.
* **In an import's string:** the folders the path can go on to: `std:`, `vendor:` and `base:` beside the compiler,
  or folders relative to the file.

Each comes with its kind, its type, and its doc comment. A file with syntax errors still completes: the parser goes on
past them. Nothing's offered in a string or a comment, or after a `.` whose name the index doesn't know the type of.

## Definitions, Hover, References and Renaming

Each check also writes the [name index](compilation.md#the-name-index), what each name in the program refers to, and
these come from the last one, so they're there once a file's package has been checked, and follow it from save to
save:

* **Go to Definition** leads from a name to where it's declared, in another package, `std`, or `base`, whose files
  are the ones beside the compiler.
* **Hover** shows a declaration's line, a local's or a field's type, and its doc comment.
* **Find All References** lists every use of a name across the program, in each of a build package's targets.
* **Rename Symbol** changes every use of a name and its declaration at once. It's refused, saying why, for a name
  declared outside the workspace, and when a file it's used in has changed since the check: save, and rename once
  it's checked.

What you've typed since the check moves with the text: a name before or after your changes is still found, and one in
them is known once the file is checked again.

What code an `#insert` puts in declares, like the functions a protocol's code makes, is found at that `#insert`: Go
to Definition leads there, and to where the name is written in the quote, when it is; hover shows its name and type;
references and completion find it. It can't be renamed, as compile-time code writes its name. The outline lists it,
once the file's been checked. An error in the code it puts in is shown where the code is written, and at the
`#insert` in the workspace that put it there, each linked to the other.

## Signatures, Highlights, Symbols and Hints

From the same index:

* **Signature help** shows the signature of the call you're typing an argument of, once you type its `(` or a `,`,
  like `scale(value : int, factor : int = 3) -> int`, with its doc comment's summary and each parameter's `@param`
  text. The parameter your argument goes to is marked: by the commas before it, or by its name in a named argument
  like `factor = 2`. A call through a value of function type, like a field, shows its type's parameters, which have no
  names. A call typed since the check is found by its name in the package, or after an imported package's name.
* **Highlighting** a name marks each place it's named in the file: its declaration, and each use.
* **Go to Symbol in Workspace** finds functions, types and constants by name, and fields, enum members and union
  variants, with the type they're in: those whose names have what you type in order, ignoring case. Names starting
  with it come first, then the workspace's, at most 500. `base` and `std` declarations the program uses are there too.
* **Inlay hints** show the type of each local whose type isn't written, like `x := 0`, a loop's variables and a
  match's bindings, after its name. A type longer than 40 characters is cut short; hovering over it shows the whole.

## Semantic Highlighting

The extension's grammar colors code by how it looks: comments, strings, numbers, keywords, built-in types like `int`.
Over that, the server colors each name by what the last check found it to be, from the same index:

| A name of | Token type | Modifiers |
|---|---|---|
| a function, or a macro | `function`, `macro` | |
| a struct, an enum | `struct`, `enum` | |
| a union, an alias or a distinct alias | `type` | |
| a constant | `variable` | `readonly` |
| a field | `property` | |
| an enum's member, a union's variant | `enumMember` | |
| a local | `variable` | `readonly` unless it can change, like `x := 0` |
| a parameter | `parameter` | `readonly` |
| an imported package | `namespace` | |

Each declaration's own name is also `declaration`; one in `base` or `std`, `defaultLibrary`; and one whose doc comment
has an `@deprecated` tag, `deprecated`. A package name before a `.`, like `compiler` in `compiler.report`, is a
`namespace` too, found from the file's imports.

The colors follow what you type, as the other answers do: a name you've changed since the check keeps the grammar's
color until the file is checked again, which the server then tells the editor, so it asks again. A file no target
reads gets its own declarations colored from its parse, with their fields, members and variants. In `base` and `std`,
whose uses the index leaves out, only declarations are colored. The extension turns
`editor.semanticHighlighting.enabled` on for Hemera files, which a theme may leave off; a theme decides the colors.

## Other Editors

`hemera-lsp` takes no arguments. It answers `initialize` with whole-document sync, open, close and save
notifications, UTF-8 positions when the client offers them, else UTF-16, and `textDocument/formatting`,
`textDocument/documentSymbol`, `textDocument/foldingRange`, `textDocument/definition`, `textDocument/hover`,
`textDocument/references`, `textDocument/prepareRename`, `textDocument/rename`, `textDocument/completion`, with
`.`, `"`, `/` and `:` as trigger characters, `textDocument/semanticTokens/full` and `textDocument/semanticTokens/range`,
with the legend above, `textDocument/signatureHelp`, with `(` and `,` as trigger characters, `textDocument/documentHighlight`,
`textDocument/inlayHint`, `workspace/symbol`, and `workspace/executeCommand` for
`hemera.checkEverything`, Check Everything, with no arguments. Its settings come in initialize's
`initializationOptions`, and later in `workspace/didChangeConfiguration`'s `settings.hemera`, as an object with
`compilerPath`, `root`, `arguments` and `checkerMemory`, named as above without `hemera.`. When the client's
capabilities say `workspace.semanticTokens.refreshSupport`, it sends `workspace/semanticTokens/refresh` after each
check, and takes the answer without a word. It exits 0 after `shutdown` and `exit`, and 1 when `exit`, or the end of
its standard input, comes without `shutdown` before it.

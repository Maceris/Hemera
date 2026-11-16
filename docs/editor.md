# Editor Support

`hemera-lsp` is Hemera's language server. An editor starts it and speaks the
[Language Server Protocol](https://microsoft.github.io/language-server-protocol/) to it over standard input and output,
and it shows the compiler's errors and warnings where they are, each time a file is opened or saved. The VS Code
extension is built with it; another editor with a language server client can start `hemera-lsp` the same way.

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

A change to `hemera.serverPath` restarts the server; the others apply from the next check.

## What's Checked, and When

Opening or saving a `.hsc` file checks the package it belongs to: `hemera.root` for a file in the workspace when it's
set, otherwise the file's own folder, as a program. The check is
[`hemera --check --diagnostics=json`](compilation.md#checking-without-building), so compile-time code runs as it would
in a build, a build package's checks included, and nothing is written but what that code writes itself.

* **Unsaved changes** in every open file are checked as they are: each goes to the compiler through `--overlay`. A file
  that's never been saved isn't seen, as packages are found by listing their folders.
* **A newer check** of a package stops the one still running, whose results are never shown.
* **Diagnostics** are shown in each file they're in, open or not, once each, though a file can be in several of a build
  package's targets. One reaches from where the compiler puts it to the end of the word or string there. A file that
  had diagnostics and has none after a check is cleared.
* **Codes** are shown as the compiler prints them, like `hemera:E4015`, so they can be searched for (see
  [Diagnostics](compilation.md#diagnostics)). Errors, warnings and what compile-time code logs below the warning level
  are shown as errors, warnings and information.

Checking as you type isn't done: a large build package can take tens of seconds to check, so checks come with opening
and saving.

## Other Editors

`hemera-lsp` takes no arguments. It answers `initialize` with whole-document sync, open, close and save
notifications, and UTF-8 positions when the client offers them, else UTF-16. Its settings come in initialize's
`initializationOptions`, and later in `workspace/didChangeConfiguration`'s `settings.hemera`, as an object with
`compilerPath`, `root` and `arguments`, named as above without `hemera.`. It exits 0 after `shutdown` and `exit`, and 1
when `exit`, or the end of its standard input, comes without `shutdown` before it.

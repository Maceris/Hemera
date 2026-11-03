"""
Turns the comments that document declarations into documentation comments (docs/documentation.md), in .hsc files:

- a /* ... */ block, or a run of // lines, directly above a declaration (no blank line between) becomes /** ... */;
- a // comment after a field, enum member or union variant, on its line, becomes /**< ... */.

A declaration is one at a package's top level, inside #if blocks there, or a member of a struct, enum or union; nothing
inside a function's body is touched. Section dividers (// ---- Name) and TODOs stay plain comments. Only the form
changes: splitting prose into @param, @return and @error is left to people.

    python tools/documentation_comments.py <file or folder>...
"""

import re
import sys
from pathlib import Path

NAME = r"[A-Za-z_][A-Za-z0-9_]*"
DIRECTIVES = r"(?:\s+#[A-Za-z_]+(?:\([^)]*\))?)*"
# name :: ..., name : type : ..., name #export :: ...
DECLARATION = re.compile(rf"^\s*{NAME}{DIRECTIVES}\s*::?(?:\s|$)")
# package name
PACKAGE = re.compile(rf"^\s*package\s+{NAME}\s*$")
# A field (name : type), an enum member (Name, Name = 1), or a union variant (Name, Name(T))
MEMBER = re.compile(rf"^\s*{NAME}(?:{DIRECTIVES}\s*:|\s*=|\s*\(|\s*,|\s*$|\s*//)")
TYPE_OPENING = re.compile(r"(?:::|\b)\s*(?:struct|enum|union)\b[^{]*\{\s*(?://.*)?$")
FN_OPENING = re.compile(r"\bfn\b.*\{\s*(?://.*)?$")
IF_OPENING = re.compile(r"^\s*(?:#if\b|}\s*#else\b|#else\b).*\{\s*(?://.*)?$")


def code_part(line: str) -> str:
    """The line without its strings' contents and its trailing // comment, for counting braces."""
    out = []
    i = 0
    in_string = False
    while i < len(line):
        c = line[i]
        if in_string:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            i += 1
            continue
        if c == "'" and i + 2 < len(line) and line[i + 2] == "'":
            i += 3
            continue
        if line.startswith("//", i):
            break
        out.append(c)
        i += 1
    return "".join(out)


def trailing_comment(line: str):
    """Where a // comment after code starts on line, or None."""
    i = 0
    in_string = False
    seen_code = False
    while i < len(line):
        c = line[i]
        if in_string:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            seen_code = True
            i += 1
            continue
        if line.startswith("//", i):
            return i if seen_code else None
        if not c.isspace():
            seen_code = True
        i += 1
    return None


def is_plain(text: str) -> bool:
    """Whether a comment's text is one to leave plain: a section divider or a TODO."""
    stripped = text.strip()
    return stripped.startswith("----") or stripped.startswith("TODO") or stripped.startswith("==")


# The widest a line may be
WIDTH = 120


def one_or_block(indent: str, texts: list) -> str:
    """A documentation comment of texts' lines: on one line if it's one that fits, else a block."""
    if len(texts) == 1 and len(indent + "/** " + texts[0].rstrip() + " */") <= WIDTH:
        return indent + "/** " + texts[0].rstrip() + " */"
    return "\n".join([indent + "/**"] + [(indent + " * " + text).rstrip() for text in texts] + [indent + " */"])


def convert(source: str) -> str:
    lines = source.split("\n")
    # Whether each line is a documentable declaration, from the blocks it's in
    stack = []
    documentable = [False] * len(lines)
    in_block_comment = False
    for index, line in enumerate(lines):
        stripped = line.strip()
        if in_block_comment:
            if "*/" in stripped:
                in_block_comment = False
            continue
        if stripped.startswith("/*") and "*/" not in stripped:
            in_block_comment = True
            continue
        if stripped.startswith("//") or stripped.startswith("/*") or not stripped:
            continue
        inside_type = bool(stack) and stack[-1] == "type"
        open_scopes = all(kind in ("if", "type") for kind in stack)
        if open_scopes:
            if inside_type and MEMBER.match(line):
                documentable[index] = True
            elif not inside_type and (DECLARATION.match(line) or PACKAGE.match(line)):
                documentable[index] = True
        # Its braces in order, so } else { closes one block and opens another
        if TYPE_OPENING.search(line) and not FN_OPENING.search(line):
            kind = "type"
        elif IF_OPENING.match(line):
            kind = "if"
        else:
            kind = "fn" if FN_OPENING.search(line) else "other"
        for c in code_part(line):
            if c == "{":
                stack.append(kind)
            elif c == "}" and stack:
                stack.pop()
    # Each documentable line's comment above it, and a member's after it
    out = list(lines)
    replaced = {}
    for index in range(len(lines)):
        if not documentable[index]:
            continue
        line = lines[index]
        # A // after it, on its line
        at = trailing_comment(line)
        if at is not None and not is_plain(line[at + 2:]) and "*/" not in line[at + 2:]:
            text = line[at + 2:].strip()
            trailing = line[:at].rstrip() + " /**< " + text + " */"
            if len(trailing) <= WIDTH:
                out[index] = trailing
            else:
                # Too long after it: above it instead
                indent = line[: len(line) - len(line.lstrip())]
                out[index] = one_or_block(indent, [text]) + "\n" + line[:at].rstrip()
        above = index - 1
        if above < 0:
            continue
        # A comment over a group of top-level declarations, each right after the last, heads the group, documenting none
        # of them alone, and stays plain
        following = index + 1
        if (not MEMBER.match(line) or DECLARATION.match(line)) and following < len(lines) and documentable[following] \
                and DECLARATION.match(lines[following]) and not line.rstrip().endswith("{"):
            continue
        previous = lines[above].strip()
        if previous.endswith("*/") and not previous.startswith("//"):
            # A block: back to its opening
            start = above
            while start >= 0 and not lines[start].lstrip().startswith("/*"):
                start -= 1
            if start < 0:
                continue
            opening = lines[start].lstrip()
            if opening.startswith("/**") or is_plain(opening[2:]):
                continue
            first = lines[start]
            position = first.index("/*")
            made = first[:position] + "/**" + first[position + 2:]
            if made.rstrip().endswith("*/") and len(made) > WIDTH:
                # One line made too long: a block
                made = one_or_block(first[:position], [made[position + 3:].rstrip()[:-2].strip()])
            replaced[start] = made
        elif previous.startswith("//"):
            start = above
            while start - 1 >= 0 and lines[start - 1].strip().startswith("//"):
                start -= 1
            texts = [lines[i].strip()[2:] for i in range(start, above + 1)]
            if any(is_plain(text) for text in texts) or any("*/" in text for text in texts):
                continue
            texts = [text[1:] if text.startswith(" ") else text for text in texts]
            comment_indent = lines[start][: len(lines[start]) - len(lines[start].lstrip())]
            replaced[start] = one_or_block(comment_indent, texts)
            for i in range(start + 1, above + 1):
                replaced[i] = None
    result = []
    for index, line in enumerate(out):
        if index in replaced:
            if replaced[index] is not None:
                result.append(replaced[index])
            continue
        result.append(line)
    return "\n".join(result)


def main() -> None:
    paths = []
    for argument in sys.argv[1:]:
        path = Path(argument)
        paths += sorted(path.rglob("*.hsc")) if path.is_dir() else [path]
    changed = 0
    for path in paths:
        # Its line endings kept as they are
        with open(path, encoding="utf-8", newline="") as file:
            source = file.read()
        crlf = "\r\n" in source
        made = convert(source.replace("\r\n", "\n"))
        if crlf:
            made = made.replace("\n", "\r\n")
        if made != source:
            with open(path, "w", encoding="utf-8", newline="") as file:
                file.write(made)
            changed += 1
    print(f"{changed} of {len(paths)} files changed")


if __name__ == "__main__":
    main()

"""
Drives hemera-lsp over standard input and output, as an editor would, with the real compiler: a package with an
error, which is published where it is; an unsaved fix, which a check sees through an overlay and clears; and a clean
shutdown. Exits 0 when all of it went as it should, 1 otherwise, saying what didn't.

    python -I drive_server.py --server path/to/hemera-lsp --compiler path/to/hemera
"""

import argparse
import json
import pathlib
import queue
import shutil
import subprocess
import sys
import tempfile
import threading

TIMEOUT_SECONDS = 120

BROKEN = "package main\n\nmain :: fn() -> int {\n    return \"not a number\"\n}\n"
FIXED = "package main\n\nmain :: fn() -> int {\n    return helper()\n}\n"
HELPER = "package main\n\nhelper :: fn() -> int {\n    return 0\n}\n"
UNFORMATTED = "package main\n\nmain :: fn( ) -> int {\n  return helper( )\n}\n"


def uri_of(path):
    return pathlib.Path(path).resolve().as_uri()


def applied(text, edit):
    """text with an edit applied, its positions in UTF-16 units, as the server was asked for."""
    lines = text.split("\n")

    def offset(position):
        before = sum(len(line) + 1 for line in lines[:position["line"]])
        line = lines[position["line"]].encode("utf-16-le")[:position["character"] * 2].decode("utf-16-le")
        return before + len(line)

    start = offset(edit["range"]["start"])
    end = offset(edit["range"]["end"])
    return text[:start] + edit["newText"] + text[end:]


class Client:
    """The server's process, with what it sends read into a queue on a thread of its own."""

    def __init__(self, server):
        self.process = subprocess.Popen([server], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.messages = queue.Queue()
        self.next_id = 1
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        stream = self.process.stdout
        while True:
            length = None
            while True:
                line = stream.readline()
                if not line:
                    return
                line = line.strip()
                if not line:
                    break
                name, _, value = line.partition(b":")
                if name.strip().lower() == b"content-length":
                    length = int(value.strip())
            self.messages.put(json.loads(stream.read(length)))

    def send(self, message):
        body = json.dumps(message).encode("utf-8")
        self.process.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        self.process.stdin.flush()

    def request(self, method, params):
        request_id = self.next_id
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})
        return self.wait_for(lambda message: message.get("id") == request_id)

    def notify(self, method, params):
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def wait_for(self, matches):
        while True:
            try:
                message = self.messages.get(timeout=TIMEOUT_SECONDS)
            except queue.Empty:
                raise AssertionError("the server said nothing for %d seconds" % TIMEOUT_SECONDS) from None
            if message.get("method") == "window/showMessage":
                raise AssertionError("the server said: " + message["params"]["message"])
            if matches(message):
                return message

    def diagnostics_for(self, uri):
        message = self.wait_for(lambda message: message.get("method") == "textDocument/publishDiagnostics"
                                and message["params"]["uri"].lower() == uri.lower())
        return message["params"]["diagnostics"]


def drive(server, compiler, folder):
    main = folder / "main.hsc"
    helper = folder / "helper.hsc"
    main.write_text(BROKEN, encoding="utf-8", newline="\n")
    helper.write_text(HELPER, encoding="utf-8", newline="\n")

    client = Client(server)
    result = client.request("initialize", {
        "processId": None,
        "rootUri": uri_of(folder),
        "capabilities": {"general": {"positionEncodings": ["utf-16"]}},
        "initializationOptions": {"compilerPath": str(compiler)},
    })
    assert result["result"]["capabilities"]["positionEncoding"] == "utf-16", result
    client.notify("initialized", {})

    # The error, where it is: line 4, at the string
    client.notify("textDocument/didOpen", {"textDocument": {"uri": uri_of(main), "languageId": "hemera", "version": 1,
                                                            "text": BROKEN}})
    diagnostics = client.diagnostics_for(uri_of(main))
    assert len(diagnostics) == 1, diagnostics
    error = diagnostics[0]
    assert error["severity"] == 1 and error["code"] == "hemera:E4015", error
    assert error["range"] == {"start": {"line": 3, "character": 11}, "end": {"line": 3, "character": 25}}, error["range"]

    # Fixed but not saved: opening another file checks with the buffer, and the error is cleared
    client.notify("textDocument/didChange", {"textDocument": {"uri": uri_of(main), "version": 2},
                                             "contentChanges": [{"text": FIXED}]})
    client.notify("textDocument/didOpen", {"textDocument": {"uri": uri_of(helper), "languageId": "hemera", "version": 1,
                                                            "text": HELPER}})
    assert client.diagnostics_for(uri_of(main)) == []

    # Tier 3, from the name index that check wrote: main's call to helper, as the unsaved buffer has it
    at_call = {"textDocument": {"uri": uri_of(main)}, "position": {"line": 3, "character": 12}}
    definition = client.request("textDocument/definition", at_call)["result"]
    assert definition and definition["uri"].lower() == uri_of(helper).lower(), definition
    assert definition["range"] == {"start": {"line": 2, "character": 0}, "end": {"line": 2, "character": 6}}, definition
    hover = client.request("textDocument/hover", at_call)["result"]
    assert hover and "helper :: fn() -> int" in hover["contents"]["value"], hover
    references = client.request("textDocument/references", dict(at_call, context={"includeDeclaration": True}))["result"]
    assert sorted(location["uri"].lower() for location in references) == sorted([uri_of(main).lower(), uri_of(helper).lower()]), references
    # Semantic tokens from the same index: main declared, and helper called, both functions
    legend = result["result"]["capabilities"]["semanticTokensProvider"]["legend"]
    data = client.request("textDocument/semanticTokens/full", {"textDocument": {"uri": uri_of(main)}})["result"]["data"]
    tokens = []
    line = start = 0
    for at in range(0, len(data), 5):
        line += data[at]
        start = start + data[at + 1] if data[at] == 0 else data[at + 1]
        modifiers = [name for bit, name in enumerate(legend["tokenModifiers"]) if data[at + 4] >> bit & 1]
        tokens.append((line, start, data[at + 2], legend["tokenTypes"][data[at + 3]], modifiers))
    assert tokens == [(2, 0, 4, "function", ["declaration"]), (3, 11, 6, "function", [])], tokens
    # Highlights, signature help, workspace symbols and inlay hints, from the same index
    highlights = client.request("textDocument/documentHighlight", at_call)["result"]
    assert [(h["range"]["start"]["line"], h["kind"]) for h in highlights] == [(3, 2)], highlights
    in_call = {"textDocument": {"uri": uri_of(main)}, "position": {"line": 3, "character": 18}}
    help_ = client.request("textDocument/signatureHelp", in_call)["result"]
    assert help_ and help_["signatures"][0]["label"] == "helper() -> int", help_
    symbols = client.request("workspace/symbol", {"query": "help"})["result"]
    # helper starts with the query, so it's first; base's names with its letters in order follow
    assert symbols and symbols[0]["name"] == "helper", symbols
    hints = client.request("textDocument/inlayHint", {"textDocument": {"uri": uri_of(main)},
                                                      "range": {"start": {"line": 0, "character": 0}, "end": {"line": 9, "character": 0}}})
    assert hints.get("result") == [], hints
    renamed = client.request("textDocument/rename", dict(at_call, newName="assist"))
    assert "error" not in renamed, renamed
    assert sum(len(edits) for edits in renamed["result"]["changes"].values()) == 2, renamed

    # Tier 2, answered in the server's own process: formatting, the outline and folding
    for capability in ("documentFormattingProvider", "documentSymbolProvider", "foldingRangeProvider"):
        assert result["result"]["capabilities"].get(capability), capability
    client.notify("textDocument/didChange", {"textDocument": {"uri": uri_of(main), "version": 3},
                                             "contentChanges": [{"text": UNFORMATTED}]})
    edits = client.request("textDocument/formatting", {"textDocument": {"uri": uri_of(main)},
                                                       "options": {"tabSize": 4, "insertSpaces": True}})["result"]
    assert len(edits) == 1, edits
    assert applied(UNFORMATTED, edits[0]) == FIXED, applied(UNFORMATTED, edits[0])

    symbols = client.request("textDocument/documentSymbol", {"textDocument": {"uri": uri_of(main)}})["result"]
    assert [(symbol["name"], symbol["kind"]) for symbol in symbols] == [("main", 12)], symbols

    folds = client.request("textDocument/foldingRange", {"textDocument": {"uri": uri_of(main)}})["result"]
    assert [(fold["startLine"], fold["endLine"]) for fold in folds] == [(2, 3)], folds

    assert "error" not in client.request("shutdown", None)
    client.notify("exit", None)
    exit_code = client.process.wait(timeout=TIMEOUT_SECONDS)
    assert exit_code == 0, "exit code %d" % exit_code


def main():
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument("--server", required=True, help="hemera-lsp")
    parser.add_argument("--compiler", required=True, help="hemera")
    arguments = parser.parse_args()
    folder = pathlib.Path(tempfile.mkdtemp(prefix="hemera_lsp_drive_"))
    try:
        drive(pathlib.Path(arguments.server).resolve(), pathlib.Path(arguments.compiler).resolve(), folder)
    except AssertionError as failure:
        print("FAILED:", failure)
        return 1
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    print("PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())

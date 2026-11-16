"""
Checks that what hemera-lsp keeps after saves, each a check of just the targets that read the saved file merged into
what it had, is what a check of everything finds: the name index and the diagnostics. It drives the real server, with
the real compiler, over a series of edits, saving each edited file, and at each "check" step asks the server for its
state, then has it check everything (hemera.checkEverything) and asks again. Exits 0 when every comparison matched, 1
otherwise, saying what differed.

    python -I compare_saves.py --server path/to/hemera-lsp --compiler path/to/hemera --steps steps.json --root src/build

The steps are compare_serve.py's, run in the folder the file is in, which they edit, so it should be a copy. An edit
is saved as an editor would: the file opened, or changed, then saved. A new file put back, so removed, is closed, and
another file in its folder saved, as no save of its own can check it. A "check" step's arguments are left out: it
compares what the saves so far left.
"""

import argparse
import json
import pathlib
import queue
import subprocess
import sys
import threading

TIMEOUT_SECONDS = 900


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
        while True:
            try:
                message = self.messages.get(timeout=TIMEOUT_SECONDS)
            except queue.Empty:
                raise AssertionError("the server said nothing for %d seconds" % TIMEOUT_SECONDS) from None
            if message.get("method") == "window/showMessage":
                raise AssertionError("the server said: " + message["params"]["message"])
            if message.get("id") == request_id:
                if "error" in message:
                    raise AssertionError("%s failed: %s" % (method, message["error"]))
                return message.get("result")

    def notify(self, method, params):
        self.send({"jsonrpc": "2.0", "method": method, "params": params})


def compared(saved, everything):
    """Lines saying how two states differ, list by list, a few examples each; empty when they're the same."""
    differences = []
    saved_roots = {root["root"]: root for root in saved["roots"]}
    for root in everything["roots"]:
        mine = saved_roots.get(root["root"], {})
        for kind in ("declarations", "uses", "readers", "diagnostics"):
            before = set(mine.get(kind, []))
            after = set(root[kind])
            if before == after:
                continue
            only_saved = sorted(before - after)
            only_everything = sorted(after - before)
            differences.append("  %s: %d only after saves, %d only after checking everything" % (kind, len(only_saved), len(only_everything)))
            differences.extend("    saves:      " + line for line in only_saved[:5])
            differences.extend("    everything: " + line for line in only_everything[:5])
    return differences


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--server", required=True)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--steps", required=True)
    parser.add_argument("--root", required=True, help="the package checked, relative to the steps' folder")
    arguments = parser.parse_args()
    steps_file = pathlib.Path(arguments.steps).resolve()
    folder = steps_file.parent
    steps = json.loads(steps_file.read_text(encoding="utf-8"))
    originals = {}
    versions = {}

    def path_of(relative):
        path = folder / relative
        if relative not in originals:
            originals[relative] = path.read_bytes() if path.exists() else None
        return path

    client = Client(str(pathlib.Path(arguments.server).resolve()))
    client.request("initialize", {
        "processId": None, "rootUri": folder.as_uri(), "capabilities": {},
        "initializationOptions": {"compilerPath": str(pathlib.Path(arguments.compiler).resolve()), "root": arguments.root,
                                  "arguments": [], "checkerMemory": 8192},
    })
    client.notify("initialized", {})

    def save(relative):
        path = folder / relative
        uri = path.resolve().as_uri()
        text = path.read_text(encoding="utf-8")
        if uri in versions:
            versions[uri] += 1
            client.notify("textDocument/didChange", {"textDocument": {"uri": uri, "version": versions[uri]},
                                                     "contentChanges": [{"text": text}]})
        else:
            versions[uri] = 1
            client.notify("textDocument/didOpen", {"textDocument": {"uri": uri, "languageId": "hemera", "version": 1, "text": text}})
        client.notify("textDocument/didSave", {"textDocument": {"uri": uri}})

    def close(relative):
        uri = (folder / relative).resolve().as_uri()
        if uri in versions:
            del versions[uri]
            client.notify("textDocument/didClose", {"textDocument": {"uri": uri}})

    compared_count = 0
    failed = 0
    started = False
    try:
        for number, step in enumerate(steps, 1):
            if "check" in step:
                if not started:
                    continue
                saved = client.request("hemera/state", {})
                client.request("workspace/executeCommand", {"command": "hemera.checkEverything"})
                everything = client.request("hemera/state", {})
                compared_count += 1
                differences = compared(saved, everything)
                if differences:
                    failed += 1
                    print("step %d: DIFFERENT" % number)
                    print("\n".join(differences))
                else:
                    counts = ", ".join("%d %s" % (len(root[kind]), kind) for root in everything["roots"]
                                       for kind in ("uses", "diagnostics"))
                    print("step %d: same (%s)" % (number, counts), flush=True)
                continue
            relative = step.get("write") or step.get("append") or step.get("replace") or step.get("restore")
            path = path_of(relative)
            if not started:
                # The first file opened: a check of everything, which the saves after it build on
                save(relative) if path.exists() else None
                client.request("hemera/state", {})
                started = True
            if "write" in step:
                path.write_text(step["text"], encoding="utf-8", newline="\n")
            elif "append" in step:
                with open(path, "a", encoding="utf-8", newline="\n") as file:
                    file.write(step["text"])
            elif "replace" in step:
                path.write_text(path.read_text(encoding="utf-8").replace(step["from"], step["to"]), encoding="utf-8", newline="\n")
            elif "restore" in step:
                original = originals[relative]
                if original is None:
                    path.unlink(missing_ok=True)
                    close(relative)
                    sibling = next(other for other in sorted(path.parent.glob("*.hsc")))
                    save(str(sibling.relative_to(folder)))
                    continue
                path.write_bytes(original)
            save(relative)
    finally:
        for relative, original in originals.items():
            path = folder / relative
            if original is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(original)
        try:
            client.request("shutdown", None)
            client.notify("exit", None)
            client.process.wait(timeout=60)
        except Exception:
            client.process.kill()
    print("%d of %d comparisons the same" % (compared_count - failed, compared_count))
    return 0 if failed == 0 and compared_count > 0 else 1


if __name__ == "__main__":
    sys.exit(main())

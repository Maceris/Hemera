"""
Checks that hemera --serve answers as a fresh hemera does, over a series of edits: each check is asked of one
long-lived --serve, restarted when it asks to be, as hemera-lsp does, and of a fresh hemera, and their exit codes,
diagnostics and name indexes are compared. Exits 0 when every check matched, 1 otherwise, saying which didn't.

    python -I compare_serve.py --compiler path/to/hemera --steps steps.json

The steps, a JSON array, run in order, in the folder the file is in, which they edit, so it should be a copy:

    {"write": "path", "text": "..."}           a file's text replaced, or a file made
    {"append": "path", "text": "..."}          text added to a file's end
    {"replace": "path", "from": "...", "to": "..."}   each "from" in a file made "to", as a rename does
    {"restore": "path"}                         a file put back as it was before the first step, or removed if it's new
    {"check": ["--targets=a", "package"]}       a check, its arguments after --check, compared
"""

import argparse
import json
import pathlib
import subprocess
import sys
import tempfile

TIMEOUT_SECONDS = 600


class Serve:
    """hemera --serve, started as needed, restarted when it asks to be, as hemera-lsp does."""

    def __init__(self, compiler, folder):
        self.compiler = compiler
        self.folder = folder
        self.process = None
        self.restarts = 0

    def start(self):
        self.process = subprocess.Popen([self.compiler, "--serve"], cwd=self.folder, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8")

    def stop(self):
        if self.process is not None:
            self.process.stdin.close()
            self.process.wait(timeout=TIMEOUT_SECONDS)
            self.process = None

    def check(self, arguments):
        for _ in range(2):
            if self.process is None:
                self.start()
            self.process.stdin.write(json.dumps({"arguments": arguments}) + "\n")
            self.process.stdin.flush()
            diagnostics = []
            while True:
                line = self.process.stdout.readline()
                if not line:
                    self.process = None
                    break
                answer = json.loads(line)
                if "done" not in answer:
                    diagnostics.append(answer)
                    continue
                if not answer["done"]:
                    # Asked of a fresh one instead
                    self.restarts += 1
                    self.stop()
                    break
                if answer.get("restart"):
                    self.stop()
                return answer["exit"], diagnostics
        raise RuntimeError("hemera --serve didn't answer")


def fresh(compiler, folder, arguments):
    run = subprocess.run([compiler, "--diagnostics=json"] + arguments, cwd=folder, capture_output=True, text=True,
                         encoding="utf-8", timeout=TIMEOUT_SECONDS)
    diagnostics = [json.loads(line) for line in run.stdout.splitlines() if line.startswith("{")]
    # hemera's -1, as a process's exit code
    return (-1 if run.returncode in (255, 4294967295) else run.returncode), diagnostics


def key(diagnostic):
    return json.dumps(diagnostic, sort_keys=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--steps", required=True)
    arguments = parser.parse_args()
    steps_file = pathlib.Path(arguments.steps).resolve()
    folder = steps_file.parent
    compiler = str(pathlib.Path(arguments.compiler).resolve())
    steps = json.loads(steps_file.read_text(encoding="utf-8"))
    original = {}
    serve = Serve(compiler, folder)
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="compare_serve_"))
    failures = 0
    checks = 0
    try:
        for number, step in enumerate(steps, 1):
            if "check" not in step:
                path = folder / (step.get("write") or step.get("append") or step.get("replace") or step.get("restore"))
                if path not in original:
                    original[path] = path.read_bytes() if path.exists() else None
                if "write" in step:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(step["text"], encoding="utf-8", newline="")
                elif "append" in step:
                    path.write_bytes(path.read_bytes() + step["text"].encode("utf-8"))
                elif "replace" in step:
                    path.write_bytes(path.read_bytes().replace(step["from"].encode("utf-8"), step["to"].encode("utf-8")))
                elif original[path] is None:
                    path.unlink(missing_ok=True)
                else:
                    path.write_bytes(original[path])
                continue
            checks += 1
            served_index = scratch / f"served_{number}.json"
            fresh_index = scratch / f"fresh_{number}.json"
            served = serve.check(["--check", f"--index={served_index}"] + step["check"])
            again = fresh(compiler, folder, ["--check", f"--index={fresh_index}"] + step["check"])
            same_exit = served[0] == again[0]
            same_diagnostics = sorted(map(key, served[1])) == sorted(map(key, again[1]))
            same_index = served_index.read_bytes() == fresh_index.read_bytes()
            if same_exit and same_diagnostics and same_index:
                print(f"step {number}: same ({len(again[1])} diagnostics, exit {again[0]})")
                continue
            failures += 1
            print(f"step {number}: DIFFERENT: exit {served[0]} against {again[0]}, "
                  f"{len(served[1])} diagnostics against {len(again[1])}, index {'same' if same_index else 'different'}")
            for line in sorted(set(map(key, served[1])) ^ set(map(key, again[1])))[:5]:
                print("   ", line)
    finally:
        serve.stop()
        for path, bytes_before in original.items():
            if bytes_before is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(bytes_before)
    print(f"{checks - failures} of {checks} checks the same; --serve restarted {serve.restarts} times")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

"""Cross-platform diff test that normalizes line endings.

`@bazel_skylib//rules:diff_test.bzl%diff_test` performs a byte-exact
comparison, which is fragile across platforms because:

  * Generators that open output files in Python text mode translate `\\n`
    to `\\r\\n` on Windows.
  * Git's `core.autocrlf` may rewrite checked-in golden files on Windows
    checkouts.

This test normalizes both inputs to LF before comparing so the same goldens
work on Linux, macOS, and Windows.
"""

import argparse
import difflib
import platform
import sys
from pathlib import Path

from python.runfiles import Runfiles


def parse_args() -> argparse.Namespace:
    """Parse command line arugments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--file1",
        required=True,
        help="The runfiles `rlocationpath` of the first file (typically the golden).",
    )
    parser.add_argument(
        "--file2",
        required=True,
        help="The runfiles `rlocationpath` of the second file (typically the actual).",
    )
    return parser.parse_args()


def rlocation(runfiles: Runfiles, rlocationpath: str) -> Path:
    """Resolve a runfile path and ensure it exists."""
    # TODO: https://github.com/periareon/rules_venv/issues/37
    source_repo = None
    if platform.system() == "Windows":
        source_repo = ""
    runfile = runfiles.Rlocation(rlocationpath, source_repo)
    if not runfile:
        raise FileNotFoundError(f"Failed to find runfile: {rlocationpath}")
    path = Path(runfile)
    if not path.exists():
        raise FileNotFoundError(f"Runfile does not exist: ({rlocationpath}) {path}")
    return path


def normalize(text: str) -> str:
    """Normalize CRLF and lone CR to LF for line-ending-tolerant comparison."""
    return text.replace("\r\n", "\n").replace("\r", "\n")


def main() -> int:
    """The maoin entrypoint"""
    args = parse_args()

    runfiles = Runfiles.Create()
    if not runfiles:
        raise EnvironmentError("Failed to locate runfiles.")

    file1 = rlocation(runfiles, args.file1)
    file2 = rlocation(runfiles, args.file2)

    text1 = normalize(file1.read_text(encoding="utf-8"))
    text2 = normalize(file2.read_text(encoding="utf-8"))

    if text1 == text2:
        return 0

    diff = "\n".join(
        difflib.unified_diff(
            text1.splitlines(),
            text2.splitlines(),
            fromfile=str(file1),
            tofile=str(file2),
            lineterm="",
        )
    )
    sys.stderr.write(
        f"Files differ after line-ending normalization:\n  file1: {file1}\n  file2: {file2}\n\n{diff}\n"
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())

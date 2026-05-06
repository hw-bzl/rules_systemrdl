"""A `diff_test` macro that ignores line-ending differences.

Drop-in replacement for `@bazel_skylib//rules:diff_test.bzl%diff_test` that
normalizes CRLF/CR to LF before comparing, so the same goldens can be used
across Linux, macOS, and Windows. Skylib's `diff_test` is byte-exact, which
fails on Windows when generators (e.g. Python tools) emit CRLF or when git
rewrites checked-in files via `core.autocrlf`.
"""

load("@rules_venv//python:defs.bzl", "py_test")

def diff_test(*, name, file1, file2, **kwargs):
    """Compare two files for equality after normalizing line endings.

    Args:
        name: Test target name.
        file1: First file label (typically a checked-in golden).
        file2: Second file label (typically the rule-generated output).
        **kwargs: Forwarded to the underlying `py_test`.
    """
    py_test(
        name = name,
        srcs = [Label("//tools/diff:diff_test.py")],
        main = str(Label("//tools/diff:diff_test.py")),
        args = [
            "--file1=$(rlocationpath {})".format(file1),
            "--file2=$(rlocationpath {})".format(file2),
        ],
        data = [file1, file2],
        deps = [Label("@rules_venv//python/runfiles")],
        **kwargs
    )

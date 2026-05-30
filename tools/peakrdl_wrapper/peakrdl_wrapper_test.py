"""Tests for the peakrdl_wrapper helper functions."""

import os
from pathlib import Path

from tools.peakrdl_wrapper.peakrdl_wrapper import (
    _format_missing_outputs_error,
    _list_dir_contents,
    _parse_wrapper_args,
    _split_argv,
)


def test_list_dir_contents_returns_empty_for_missing_dir() -> None:
    """Returns an empty list when the directory doesn't exist."""
    assert not _list_dir_contents("/tmp/definitely_not_a_real_directory_xyz")


def test_list_dir_contents_returns_sorted_relative_paths(tmp_path: Path) -> None:
    """Lists files in sorted order, relative to the directory."""
    for name in ["b.sv", "a.sv", "c_pkg.sv"]:
        (tmp_path / name).write_text("")
    assert _list_dir_contents(str(tmp_path)) == ["a.sv", "b.sv", "c_pkg.sv"]


def test_list_dir_contents_walks_subdirectories(tmp_path: Path) -> None:
    """Walks subdirectories and includes their files with relative paths."""
    (tmp_path / "sub").mkdir()
    (tmp_path / "top.txt").write_text("")
    (tmp_path / "sub" / "nested.txt").write_text("")
    assert _list_dir_contents(str(tmp_path)) == [
        os.path.join("sub", "nested.txt"),
        "top.txt",
    ]


def test_format_missing_outputs_error_lists_missing_paths() -> None:
    """The formatted error names every missing output path."""
    msg = _format_missing_outputs_error(["/some/path/foo.sv", "/some/path/foo_pkg.sv"])
    assert "Missing outputs:" in msg
    assert "/some/path/foo.sv" in msg
    assert "/some/path/foo_pkg.sv" in msg


def test_format_missing_outputs_error_includes_actionable_fixes() -> None:
    """The formatted error suggests three concrete fixes the user can apply."""
    msg = _format_missing_outputs_error(["/x/foo.sv"])
    assert "rename the addrmap declaration" in msg
    assert "rename the target" in msg
    assert "output_name" in msg


def test_format_missing_outputs_error_lists_actual_dir_contents(tmp_path: Path) -> None:
    """Files that peakrdl actually produced are surfaced alongside the missing list."""
    (tmp_path / "actually_produced.sv").write_text("")
    msg = _format_missing_outputs_error([str(tmp_path / "expected.sv")])
    assert "actually_produced.sv" in msg


def test_format_missing_outputs_error_reports_empty_dir(tmp_path: Path) -> None:
    """An empty target directory is explicitly labeled `(empty)`."""
    msg = _format_missing_outputs_error([str(tmp_path / "expected.sv")])
    assert "(empty)" in msg


def test_split_argv_separates_around_double_dash() -> None:
    """`--` separates wrapper args from peakrdl args."""
    wrapper, peakrdl = _split_argv(["--bazel-outputs=a,b", "--", "regblock", "foo.rdl"])
    assert wrapper == ["--bazel-outputs=a,b"]
    assert peakrdl == ["regblock", "foo.rdl"]


def test_parse_wrapper_args_extracts_outputs() -> None:
    """`--bazel-outputs=A,B` parses to the list `[A, B]` with empties dropped."""
    assert _parse_wrapper_args(["--bazel-outputs=a,b,"]) == ["a", "b"]

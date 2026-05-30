"""rules_systemrdl wrapper for peakrdl.

Parses ``--bazel-outputs=PATH,PATH`` from the leading args, then forwards
everything after ``--`` to ``peakrdl_main`` unchanged. After peakrdl returns,
verifies each declared output exists on disk; if any are missing, lists what
peakrdl actually produced in the same directory and prints an actionable
error.

Invocation shape (set by the rule):
    peakrdl_wrapper --bazel-outputs=PATH,PATH -- <peakrdl args...>
"""

import argparse
import os
import sys
from typing import List, Sequence, Tuple

from peakrdl.main import main as peakrdl_main


def _split_argv(argv: Sequence[str]) -> Tuple[List[str], List[str]]:
    if "--" not in argv:
        sys.stderr.write(
            "rules_systemrdl: internal error: peakrdl_wrapper requires `--` "
            f"to separate wrapper args from peakrdl args. Got: {list(argv)}\n"
        )
        sys.exit(2)
    sep = list(argv).index("--")
    return list(argv[:sep]), list(argv[sep + 1 :])


def _parse_wrapper_args(wrapper_argv: Sequence[str]) -> List[str]:
    parser = argparse.ArgumentParser(add_help=False, prog="peakrdl_wrapper")
    parser.add_argument("--bazel-outputs", required=True, dest="bazel_outputs")
    opts, leftover = parser.parse_known_args(list(wrapper_argv))
    if leftover:
        sys.stderr.write(
            f"rules_systemrdl: internal error: unexpected wrapper args: {leftover}\n"
        )
        sys.exit(2)
    return [p for p in opts.bazel_outputs.split(",") if p]


def _list_dir_contents(dirpath: str) -> List[str]:
    if not os.path.isdir(dirpath):
        return []
    entries: List[str] = []
    for root, _dirs, files in os.walk(dirpath):
        for name in files:
            rel = os.path.relpath(os.path.join(root, name), dirpath)
            entries.append(rel)
    entries.sort()
    return entries


_MISSING_OUTPUTS_TEMPLATE = """\
rules_systemrdl: peakrdl ran successfully but did not produce the outputs Bazel declared.

Missing outputs:
{missing_block}

Files peakrdl actually produced:
{produced_block}

This usually means the target name does not match the top-level addrmap declaration in the root .rdl file. Fix one of:
  - rename the addrmap declaration to match the target name
  - rename the target to match the addrmap name
  - set `output_name = "<addrmap_name>"` on the system_rdl_library
"""


def _format_missing_outputs_error(missing: Sequence[str]) -> str:
    missing_block = "\n".join(f"  - {p}" for p in missing)

    produced_lines: List[str] = []
    any_produced = False
    seen_dirs: set[str] = set()
    for p in missing:
        d = os.path.dirname(p) or "."
        if d in seen_dirs:
            continue
        seen_dirs.add(d)
        contents = _list_dir_contents(d)
        if contents:
            any_produced = True
            produced_lines.append(f"  in {d}/:")
            produced_lines.extend(f"    - {c}" for c in contents)
        else:
            produced_lines.append(f"  in {d}/: (empty)")
    if not any_produced:
        produced_lines.append("  (no files produced)")

    return _MISSING_OUTPUTS_TEMPLATE.format(
        missing_block=missing_block,
        produced_block="\n".join(produced_lines),
    )


def main() -> None:
    """Entrypoint: parse wrapper args, run peakrdl, verify declared outputs exist."""
    wrapper_argv, peakrdl_argv = _split_argv(sys.argv[1:])
    expected_outputs = _parse_wrapper_args(wrapper_argv)

    sys.argv = [sys.argv[0]] + peakrdl_argv
    peakrdl_main()

    missing = [p for p in expected_outputs if not os.path.exists(p)]
    if missing:
        sys.stderr.write(_format_missing_outputs_error(missing))
        sys.exit(1)


if __name__ == "__main__":
    main()

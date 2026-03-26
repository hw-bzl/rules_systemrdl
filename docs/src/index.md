# rules_systemrdl

Bazel rules for [SystemRDL](https://peakrdl.readthedocs.io/en/latest/systemrdl-tutorial.html).

## Overview

`rules_systemrdl` integrates PeakRDL with Bazel:

- **`system_rdl_library`** — compile `.rdl` sources with configured exporters (e.g. regblock, HTML).
- **`system_rdl_toolchain`** — configure PeakRDL, exporters, and default exporter arguments.
- **`verilog_system_rdl_library`** — wrap SystemRDL exporter output as a Verilog library (`VerilogInfo`).
- **`SystemRdlInfo`** — provider describing SystemRDL sources and root file.

Rule API details are generated from the Starlark sources in the sections linked from [Summary](./SUMMARY.md).

## Quick start

Add to `MODULE.bazel`:

```python
bazel_dep(name = "rules_systemrdl", version = "…")

register_toolchains(
    # your repository’s registered toolchain target, e.g.
    "//tools/toolchains:system_rdl_toolchain",
)
```

Load rules from `@rules_systemrdl//systemrdl:defs.bzl` or from the individual `.bzl` files documented in this book.

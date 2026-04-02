"""# SystemRDL rules.

Bazel rules for [SystemRDL](https://peakrdl.readthedocs.io/en/latest/systemrdl-tutorial.html)

## Setup

```python
bazel_dep(name = "rules_systemrdl", version = "{version}")

# Register your own toolchain.
register_toolchain(
    "//tools/toolchains:system_rdl_toolchain",
)
```
"""

load(
    ":system_rdl_info.bzl",
    _SystemRdlInfo = "SystemRdlInfo",
)
load(
    ":system_rdl_library.bzl",
    _system_rdl_library = "system_rdl_library",
)
load(
    ":system_rdl_toolchain.bzl",
    _system_rdl_toolchain = "system_rdl_toolchain",
)
load(
    ":verilog_system_rdl_library.bzl",
    _verilog_system_rdl_library = "verilog_system_rdl_library",
)
load(
    ":vhdl_system_rdl_library.bzl",
    _vhdl_system_rdl_library = "vhdl_system_rdl_library",
)

SystemRdlInfo = _SystemRdlInfo
system_rdl_library = _system_rdl_library
system_rdl_toolchain = _system_rdl_toolchain
verilog_system_rdl_library = _verilog_system_rdl_library
vhdl_system_rdl_library = _vhdl_system_rdl_library

"""# SystemRDL rules"""

load(
    ":system_rdl_info.bzl",
    _SystemRdlInfo = "SystemRdlInfo",
)
load(
    ":system_rdl_library.bzl",
    _system_rdl_library = "system_rdl_library",
)
load(
    ":system_rdl_output.bzl",
    _system_rdl_output = "system_rdl_output",
)
load(
    ":system_rdl_toolchain.bzl",
    _system_rdl_toolchain = "system_rdl_toolchain",
)
load(
    ":verilog_system_rdl_library.bzl",
    _verilog_system_rdl_library = "verilog_system_rdl_library",
)

SystemRdlInfo = _SystemRdlInfo
system_rdl_library = _system_rdl_library
system_rdl_output = _system_rdl_output
system_rdl_toolchain = _system_rdl_toolchain
verilog_system_rdl_library = _verilog_system_rdl_library

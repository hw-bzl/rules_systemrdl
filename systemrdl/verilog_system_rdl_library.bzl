"""verilog_system_rdl_library"""

load("@rules_verilog//verilog:verilog_info.bzl", "VerilogInfo")
load("//systemrdl/private:system_rdl.bzl", "TOOLCHAIN_TYPE")
load(":system_rdl_info.bzl", "SystemRdlInfo")

def _verilog_system_rdl_library_impl(ctx):
    lib = ctx.attr.lib

    if OutputGroupInfo not in lib:
        fail("No output groups were found in `lib` - `{}`".format(
            lib.label,
        ))

    toolchain = ctx.toolchains[TOOLCHAIN_TYPE]
    output_group = "system_rdl_{}".format(ctx.attr.exporter)
    if not hasattr(lib[OutputGroupInfo], output_group):
        fail("system_rdl_library `{}` does not have a `{}` output. Is the current toolchain configured for this? `{}`".format(
            lib.label,
            ctx.attr.exporter,
            toolchain.label,
        ))

    srcs = getattr(lib[OutputGroupInfo], output_group)

    return [
        DefaultInfo(
            files = srcs,
        ),
        VerilogInfo(
            srcs = srcs,
            hdrs = depset(),
            includes = depset(),
            data = depset(),
            deps = depset(),
        ),
    ]

verilog_system_rdl_library = rule(
    doc = "A rule which extracts a `verilog_library` from a `system_rdl_library`.",
    implementation = _verilog_system_rdl_library_impl,
    attrs = {
        "exporter": attr.string(
            doc = "The SystemRDL exporter whose output should be wrapped as a Verilog library.",
            default = "regblock",
        ),
        "lib": attr.label(
            doc = "The `system_rdl_library` to extract Verilog from.",
            mandatory = True,
            providers = [SystemRdlInfo],
        ),
    },
    provides = [VerilogInfo],
    toolchains = [TOOLCHAIN_TYPE],
)

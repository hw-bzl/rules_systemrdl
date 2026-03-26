"""Transition rule for applying extra toolchains in tests."""

load("//systemrdl/private:system_rdl.bzl", "SystemRdlInfo")

def _extra_toolchain_transition_impl(settings, attr):
    return {
        "//command_line_option:extra_toolchains": [
            attr.extra_toolchain,
        ] + settings["//command_line_option:extra_toolchains"],
    }

_extra_toolchain_transition = transition(
    implementation = _extra_toolchain_transition_impl,
    inputs = ["//command_line_option:extra_toolchains"],
    outputs = ["//command_line_option:extra_toolchains"],
)

def _with_extra_toolchain_impl(ctx):
    target = ctx.attr.target[0]
    providers = [target[DefaultInfo], target[OutputGroupInfo]]
    if SystemRdlInfo in target:
        providers.append(target[SystemRdlInfo])
    return providers

with_extra_toolchain = rule(
    doc = "Apply an extra toolchain via transition and forward providers from the inner target.",
    implementation = _with_extra_toolchain_impl,
    attrs = {
        "extra_toolchain": attr.string(
            doc = "Label string of the toolchain() target to prepend to extra_toolchains.",
            mandatory = True,
        ),
        "target": attr.label(
            doc = "The target to build under the transitioned toolchain.",
            cfg = _extra_toolchain_transition,
            mandatory = True,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

"""Starlark tests for `verilog_system_rdl_library`."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_verilog//verilog:verilog_info.bzl", "VerilogInfo")
load("//systemrdl:verilog_system_rdl_library.bzl", "verilog_system_rdl_library")

def _verilog_provider_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    verilog = target[VerilogInfo]
    srcs = verilog.srcs.to_list()

    asserts.equals(env, 2, len(srcs), "Expected only two regblock sources")

    expected = [".sv", "_pkg.sv"]
    found = []
    for src in srcs:
        if src.basename.endswith("_pkg.sv"):
            found.append("_pkg.sv")
            continue
        if src.basename.endswith(".sv"):
            found.append(".sv")
            continue

    asserts.equals(env, sorted(found), expected, "Failed to find srcs with expected suffix `{}`. Found `{}` from `{}`".format(
        expected,
        found,
        srcs,
    ))

    asserts.equals(env, [], verilog.hdrs.to_list(), "hdrs should be empty")
    asserts.equals(env, [], verilog.includes.to_list(), "includes should be empty")
    asserts.equals(env, [], verilog.data.to_list(), "data should be empty")
    asserts.equals(env, [], verilog.deps.to_list(), "deps should be empty")

    return analysistest.end(env)

verilog_system_rdl_library_provider_test = analysistest.make(
    _verilog_provider_test_impl,
)

def verilog_system_rdl_library_test_suite(*, name, **kwargs):
    verilog_system_rdl_library(
        name = "atxmega_spi_lib",
        lib = "//systemrdl/private/tests/simple:atxmega_spi",
    )

    verilog_system_rdl_library_provider_test(
        name = "verilog_system_rdl_library_provider_test",
        target_under_test = ":atxmega_spi_lib",
    )

    native.test_suite(
        name = name,
        tests = [
            ":verilog_system_rdl_library_provider_test",
        ],
        **kwargs
    )

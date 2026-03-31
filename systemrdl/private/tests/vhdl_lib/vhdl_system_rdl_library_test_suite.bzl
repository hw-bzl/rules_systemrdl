"""Starlark tests for `vhdl_system_rdl_library`."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_vhdl//vhdl:vhdl_info.bzl", "VhdlInfo")
load("//systemrdl:vhdl_system_rdl_library.bzl", "vhdl_system_rdl_library")

def _vhdl_provider_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    vhdl = target[VhdlInfo]
    srcs = vhdl.srcs.to_list()

    asserts.equals(env, 1, len(srcs), "Expected exactly one regblock source")
    asserts.equals(env, [], vhdl.data.to_list(), "data should be empty")
    asserts.equals(env, [], vhdl.deps.to_list(), "deps should be empty")
    asserts.equals(env, "work", vhdl.library, "library should default to 'work'")
    asserts.equals(env, "", vhdl.standard, "standard should default to empty")

    return analysistest.end(env)

def _vhdl_custom_library_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    vhdl = target[VhdlInfo]

    asserts.equals(env, "my_lib", vhdl.library, "library should match custom value")
    asserts.equals(env, 1, len(vhdl.srcs.to_list()), "Expected exactly one regblock source")

    return analysistest.end(env)

vhdl_system_rdl_library_provider_test = analysistest.make(
    _vhdl_provider_test_impl,
)

vhdl_system_rdl_library_custom_library_test = analysistest.make(
    _vhdl_custom_library_test_impl,
)

def vhdl_system_rdl_library_test_suite(*, name, **kwargs):
    """Test suite for `vhdl_system_rdl_library`.

    Args:
      name: The `test_suite` target name.
      **kwargs: Forwarded to `native.test_suite`.
    """
    vhdl_system_rdl_library(
        name = "atxmega_spi_vhdl_lib",
        exporter = "regblock",
        lib = "//systemrdl/private/tests/simple:atxmega_spi",
    )

    vhdl_system_rdl_library(
        name = "atxmega_spi_vhdl_lib_custom",
        exporter = "regblock",
        lib = "//systemrdl/private/tests/simple:atxmega_spi",
        library = "my_lib",
    )

    vhdl_system_rdl_library_provider_test(
        name = "vhdl_system_rdl_library_provider_test",
        target_under_test = ":atxmega_spi_vhdl_lib",
    )

    vhdl_system_rdl_library_custom_library_test(
        name = "vhdl_system_rdl_library_custom_library_test",
        target_under_test = ":atxmega_spi_vhdl_lib_custom",
    )

    native.test_suite(
        name = name,
        tests = [
            ":vhdl_system_rdl_library_provider_test",
            ":vhdl_system_rdl_library_custom_library_test",
        ],
        **kwargs
    )

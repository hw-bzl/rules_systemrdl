"""Starlark tests for `vhdl_system_rdl_library`."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_vhdl//vhdl:vhdl_info.bzl", "VhdlInfo")
load("//systemrdl:vhdl_system_rdl_library.bzl", "vhdl_system_rdl_library")

# The registered test toolchain in this repo only declares the `regblock`
# exporter, so these analysis tests point `vhdl_system_rdl_library` at it
# via the `exporter` attr. The wrapping into `VhdlInfo` (library / standard /
# deps handling) is exporter-agnostic, so this exercises the same code path
# that a `regblock-vhdl`-registered toolchain would.

def _vhdl_provider_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    vhdl = target[VhdlInfo]

    asserts.equals(env, [], vhdl.data.to_list(), "data should be empty")
    asserts.equals(env, [], vhdl.deps.to_list(), "deps should be empty")
    asserts.equals(env, "", vhdl.top_entity, "top_entity should be empty")
    asserts.equals(env, "atxmega_spi", vhdl.library, "library should default to `label.name` of `lib`")
    asserts.equals(env, "", vhdl.standard, "standard should default to the empty string")

    return analysistest.end(env)

vhdl_system_rdl_library_provider_test = analysistest.make(
    _vhdl_provider_test_impl,
)

def _vhdl_explicit_library_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    vhdl = target[VhdlInfo]

    asserts.equals(env, "custom_lib_name", vhdl.library, "explicit `library` attr should be forwarded to `VhdlInfo.library`")
    asserts.equals(env, "2008", vhdl.standard, "explicit `standard` attr should be forwarded to `VhdlInfo.standard`")

    return analysistest.end(env)

vhdl_system_rdl_library_explicit_library_test = analysistest.make(
    _vhdl_explicit_library_test_impl,
)

def vhdl_system_rdl_library_test_suite(*, name, **kwargs):
    """Entry point for `vhdl_system_rdl_library` analysis tests.

    Args:
        name: The name of the generated `test_suite`.
        **kwargs: Additional keyword arguments forwarded to `test_suite`.
    """
    vhdl_system_rdl_library(
        name = "atxmega_spi_lib",
        exporter = "regblock",
        lib = "//systemrdl/private/tests/simple:atxmega_spi",
    )

    vhdl_system_rdl_library_provider_test(
        name = "vhdl_system_rdl_library_provider_test",
        target_under_test = ":atxmega_spi_lib",
    )

    vhdl_system_rdl_library(
        name = "atxmega_spi_lib_explicit",
        exporter = "regblock",
        lib = "//systemrdl/private/tests/simple:atxmega_spi",
        library = "custom_lib_name",
        standard = "2008",
    )

    vhdl_system_rdl_library_explicit_library_test(
        name = "vhdl_system_rdl_library_explicit_library_test",
        target_under_test = ":atxmega_spi_lib_explicit",
    )

    native.test_suite(
        name = name,
        tests = [
            ":vhdl_system_rdl_library_provider_test",
            ":vhdl_system_rdl_library_explicit_library_test",
        ],
        **kwargs
    )

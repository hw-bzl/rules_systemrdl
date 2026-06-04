"""# vhdl_system_rdl_library"""

load("@rules_vhdl//vhdl:vhdl_info.bzl", "VhdlInfo")
load("//systemrdl/private:system_rdl.bzl", "TOOLCHAIN_TYPE")
load(":system_rdl_info.bzl", "SystemRdlInfo")

def _vhdl_system_rdl_library_impl(ctx):
    lib = ctx.attr.lib

    toolchain = ctx.toolchains[TOOLCHAIN_TYPE]
    exporter = ctx.attr.exporter
    descriptors = toolchain.exporter_outputs.get(exporter)
    if descriptors == None:
        fail((
            "The resolved SystemRDL toolchain does not register the `{exporter}` " +
            "exporter, which `{label}` requires. Configure the toolchain " +
            "(see `system_rdl_toolchain`'s `exporter_outputs`) and ensure " +
            "the matching peakrdl plugin is available on the toolchain's " +
            "`peakrdl` PyInfo. Known exporters: `{known}`."
        ).format(
            exporter = exporter,
            label = ctx.label,
            known = sorted(toolchain.exporter_outputs.keys()),
        ))

    if OutputGroupInfo not in lib:
        fail("No output groups were found in `lib` - `{}`".format(
            lib.label,
        ))

    available_ids = [d.id for d in descriptors]
    requested_ids = list(ctx.attr.extract) if ctx.attr.extract else available_ids
    for requested in requested_ids:
        if requested not in available_ids:
            fail((
                "`{label}` requested output id `{id}` from exporter " +
                "`{exporter}`, but the resolved SystemRDL toolchain only " +
                "registers `{available}` for it."
            ).format(
                label = ctx.label,
                id = requested,
                exporter = exporter,
                available = available_ids,
            ))

    combined_group = "system_rdl_{}".format(exporter)
    if not hasattr(lib[OutputGroupInfo], combined_group):
        fail((
            "`system_rdl_library` `{lib}` did not emit the `{group}` " +
            "output group expected by `{label}`. The toolchain registers " +
            "`{exporter}`, so the library should have produced this " +
            "group — check that `{lib}` actually exercises this exporter " +
            "(its `exporter_args` should include `{exporter}` or the " +
            "toolchain should supply default args for it)."
        ).format(
            lib = lib.label,
            label = ctx.label,
            exporter = exporter,
            group = combined_group,
        ))

    srcs_depsets = []
    for requested in requested_ids:
        per_id_group = "{}_{}".format(combined_group, requested)
        srcs_depsets.append(getattr(lib[OutputGroupInfo], per_id_group))
    srcs = depset(transitive = srcs_depsets)

    dep_infos = [dep[VhdlInfo] for dep in ctx.attr.deps]

    return [
        DefaultInfo(
            files = srcs,
        ),
        VhdlInfo(
            srcs = srcs,
            data = depset(),
            library = ctx.attr.library,
            standard = ctx.attr.standard,
            top_entity = "",
            deps = depset(
                dep_infos,
                order = "postorder",
                transitive = [d.deps for d in dep_infos],
            ),
        ),
    ]

vhdl_system_rdl_library = rule(
    doc = "A rule which extracts a `vhdl_library` from a `system_rdl_library`.",
    implementation = _vhdl_system_rdl_library_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "Additional `vhdl_library`-providing dependencies.",
            providers = [VhdlInfo],
        ),
        "exporter": attr.string(
            doc = "The SystemRDL exporter whose output should be wrapped as a VHDL library.",
            default = "regblock-vhdl",
        ),
        "extract": attr.string_list(
            doc = (
                "Output ids (from the toolchain's `exporter_outputs` " +
                "descriptors for this exporter) to wrap into the " +
                "`VhdlInfo`. Defaults to all ids the exporter declares."
            ),
        ),
        "lib": attr.label(
            doc = "The `system_rdl_library` to extract VHDL from.",
            mandatory = True,
            providers = [SystemRdlInfo],
        ),
        "library": attr.string(
            doc = "VHDL library name this target compiles into.",
            default = "work",
        ),
        "standard": attr.string(
            doc = "VHDL standard version. Empty string means not specified; consumer rules apply their default.",
            default = "",
            values = ["", "1993", "2000", "2002", "2008", "2019"],
        ),
    },
    provides = [VhdlInfo],
    toolchains = [TOOLCHAIN_TYPE],
)

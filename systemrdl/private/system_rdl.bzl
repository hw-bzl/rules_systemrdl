"""SystemRDL Bazel rules"""

load("@rules_venv//python:py_info.bzl", "PyInfo")

TOOLCHAIN_TYPE = str(Label("//systemrdl:toolchain_type"))

SystemRdlInfo = provider(
    doc = "Info for SystemRDL targets.",
    fields = {
        "outputs": "Dict[str, Depset[File]]: A mapping of exporter names to their outputs.",
        "root": "File: The top level source file for a library.",
        "srcs": "Depset[File]: All (including transitive) source files.",
    },
)

def _dirname_map(file):
    return file.dirname

def _extract_rename(exporter_args):
    found_rename = False
    for arg in exporter_args:
        if found_rename:
            return arg
        if arg.startswith("--rename="):
            _, _, value = arg.partition("=")
            return value
        if arg == "--rename":
            found_rename = True
    return None

def _system_rdl_library_impl(ctx):
    # Collect sources ensuring that root is removed from source list so it
    # can be provided last to maintain "dependencies first, top-level last" order.
    # https://peakrdl.readthedocs.io/en/latest/processing-input.html
    root = ctx.file.root
    srcs = []
    if not root:
        if len(ctx.files.srcs) == 1:
            root = ctx.files.srcs[0]
        else:
            for src in ctx.files.srcs:
                basename, _, _ = src.basename.rpartition(".")
                if basename != ctx.label.name:
                    srcs.append(src)
                    continue
                if root:
                    fail("Multiple source files match candidates for `root`. Please explicitly assign one to this attribute for {}".format(
                        ctx.label,
                    ))
                root = src

    srcs = depset([root] + srcs, transitive = [dep[SystemRdlInfo].srcs for dep in ctx.attr.deps], order = "preorder")

    toolchain = ctx.toolchains[TOOLCHAIN_TYPE]

    exporter_outs = {}
    output_groups = {}
    for exporter in ctx.attr.exporter_args:
        if exporter not in toolchain.exporter_files and exporter not in toolchain.exporter_dirs:
            fail("Unsupported exporter command '{}'. Please update `{}` to use one of `{}`".format(
                exporter,
                ctx.label,
                sorted(depset(toolchain.exporter_files.keys() + toolchain.exporter_dirs.keys()).to_list()),
            ))

    rename_values = {}
    for exporter, exporter_args in ctx.attr.exporter_args.items():
        rename = _extract_rename(exporter_args)
        if rename != None:
            rename_values[exporter] = rename

    for exporters, is_file_output in [
        (toolchain.exporter_files, True),
        (toolchain.exporter_dirs, False),
    ]:
        for exporter, extension in exporters.items():
            rename = rename_values.get(exporter)
            if rename != None:
                output_name = rename
            elif ctx.attr.output_name:
                output_name = ctx.attr.output_name
            else:
                output_name = ctx.label.name

            output_group_name = "system_rdl_{}".format(exporter)
            outputs = []
            for ext in extension.split(","):
                if is_file_output:
                    name = "{}{}".format(output_name, ext)
                    output = ctx.actions.declare_file(name)
                    outputs.append(output)
                    output_groups["{}{}".format(output_group_name, ext.replace(".", "_"))] = depset([output])
                else:
                    name = "{}{}".format(output_name, ext)
                    output = ctx.actions.declare_directory(name)
                    outputs.append(output)
                    output_groups["{}{}".format(output_group_name, ext)] = depset([output])

            args = ctx.actions.args()
            args.add_joined("--bazel-outputs", outputs, join_with = ",", expand_directories = False)
            args.add("--")
            args.add("--peakrdl-cfg", toolchain.peakrdl_config)
            args.add(exporter)
            args.add_all(srcs)
            args.add_all(toolchain.default_exporter_args.get(exporter, []))
            args.add_all(ctx.attr.exporter_args.get(exporter, []))
            args.add_all(
                outputs,
                before_each = "-o",
                expand_directories = False,
                uniquify = True,
                map_each = _dirname_map if is_file_output else None,
            )

            ctx.actions.run(
                mnemonic = "SystemRdl{}".format(exporter.capitalize()),
                outputs = outputs,
                executable = ctx.executable._peakrdl,
                arguments = [args],
                inputs = srcs,
                tools = [toolchain.peakrdl_config],
                execution_requirements = {"supports-path-mapping": ""},
            )

            output_set = depset(outputs)
            exporter_outs[exporter] = output_set
            output_groups[output_group_name] = output_set

    return [
        DefaultInfo(
            files = srcs,
        ),
        OutputGroupInfo(
            **output_groups
        ),
        SystemRdlInfo(
            srcs = srcs,
            root = root,
            outputs = exporter_outs,
        ),
    ]

system_rdl_library = rule(
    doc = """\
A SystemRDL library.

Outputs of these rules are generally extracted via a [`filegroup`](https://bazel.build/reference/be/general#filegroup).

```python
load("@rules_verilog//systemrdl:system_rdl_library.bzl", "system_rdl_library")

system_rdl_library(
    name = "atxmega_spi",
    srcs = ["atxmega_spi.rdl"],
    exporter_args = {
        "regblock": [
            "--cpuif",
            "axi4-lite-flat",
        ],
    },
)

filegroup(
    name = "atxmega_spi.sv",
    srcs = ["atxmega_spi"],
    output_group = "system_rdl_regblock",
)
```
""",
    implementation = _system_rdl_library_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "Additional `system_rdl_library` dependencies.",
            providers = [SystemRdlInfo],
        ),
        "exporter_args": attr.string_list_dict(
            doc = "A mapping of exporter names to arguments.",
        ),
        "output_name": attr.string(
            doc = "Basename used for declared outputs (and validated against the root file's top-level addrmap). Defaults to the target name. Use this when the addrmap name in the SystemRDL source differs from the target name.",
        ),
        "root": attr.label(
            doc = "The top source file of the SystemRDL library.",
            allow_single_file = [".rdl"],
        ),
        "srcs": attr.label_list(
            doc = "Source files which define the entire SystemRDL dag.",
            allow_files = [".rdl"],
            mandatory = True,
        ),
        "_peakrdl": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//systemrdl/private:peakrdl"),
        ),
    },
    toolchains = [TOOLCHAIN_TYPE],
)

def _get_output_groups(group_info):
    groups = []
    for entry in dir(group_info):
        if entry.startswith("system_rdl_"):
            groups.append(entry)

    return groups

def _system_rdl_output_impl(ctx):
    if ctx.attr.exporter and ctx.attr.output_group:
        fail("`exporter` and `output_group` are mutually exclusive for `system_rdl_output`. Please update `{}`".format(
            ctx.label,
        ))

    if ctx.attr.exporter:
        rdl_info = ctx.attr.lib[SystemRdlInfo]
        outputs = rdl_info.outputs.get(ctx.attr.exporter)
        if not outputs:
            fail("`{}` does not use exporter `{}`. Use one of: `{}`".format(
                ctx.attr.lib.label,
                ctx.attr.exporter,
                rdl_info.outputs.keys(),
            ))

        return [DefaultInfo(
            files = outputs,
        )]

    if ctx.attr.output_group:
        group_info = ctx.attr.lib[OutputGroupInfo]
        group = getattr(group_info, ctx.attr.output_group, None)
        if not group:
            fail("`{}` does not output_group `{}`. Use one of: `{}`".format(
                ctx.attr.lib.label,
                ctx.attr.output_group,
                _get_output_groups(group_info),
            ))

        return [DefaultInfo(
            files = group,
        )]

    fail("Either `exporter` or `output_group` is required for `system_rdl_output`. Please update `{}`".format(
        ctx.label,
    ))

system_rdl_output = rule(
    doc = """\
An accessor for `system_rdl_library` targets.

Outputs can be accessed using a `filegroup` via `output_group` but
that rule will not error if you specified an invalid output group.
Consumers who want to guarantee the outputs are generated from
`system_rdl_library` should use this rule
""",
    implementation = _system_rdl_output_impl,
    attrs = {
        "exporter": attr.string(
            doc = "The exporter to select outputs from. Mutually exclusive with `output_Group`.",
        ),
        "lib": attr.label(
            doc = "The SystemRDL library.",
            mandatory = True,
            providers = [SystemRdlInfo, OutputGroupInfo],
        ),
        "output_group": attr.string(
            doc = "The output group to forward. Mutually exclusive with `exporter`.",
        ),
    },
)

def _system_rdl_toolchain_impl(ctx):
    all_exporters = []
    for group in [ctx.attr.exporter_files, ctx.attr.exporter_dirs]:
        for exporter in group:
            if " " in exporter:
                fail("`{}` has an exporter with an illegal name: `{}`".format(
                    ctx.label,
                    exporter,
                ))

            if exporter in all_exporters:
                fail("`{}` has a duplicate exporter: `{}`".format(
                    ctx.label,
                    exporter,
                ))
            all_exporters.append(exporter)

    for key in ctx.attr.exporter_args:
        if key not in ctx.attr.exporters:
            fail("Args were given for `{}` but it's not a known exporter `{}`. Please update `{}`".format(
                key,
                sorted(ctx.attr.exporters.keys()),
                ctx.label,
            ))

    return [
        platform_common.ToolchainInfo(
            exporter_files = ctx.attr.exporter_files,
            exporter_dirs = ctx.attr.exporter_dirs,
            default_exporter_args = ctx.attr.exporter_args,
            peakrdl = ctx.attr.peakrdl,
            peakrdl_config = ctx.file.peakrdl_config,
        ),
    ]

system_rdl_toolchain = rule(
    doc = """\
A SystemRDL toolchain.

Plugins:

[Additional exporters](https://peakrdl.readthedocs.io/en/latest/for-devs/exporter-plugin.html)
are supported via a combination of the `peakrdl` and `peakrdl_config` attributes.

```python
load("@rules_venv//python:py_library.bzl", "py_library")
load("@rules_systemrdl//systemrdl:system_rdl_toolchain.bzl", "system_rdl_toolchain")

py_library(
    name = "peakrdl_toml",
    srcs = ["peakrdl_toml.py"],
    deps = [
        "@pip_deps//peakrdl",
        "@pip_deps//tomli",
    ],
)

PLUGINS = [
    ":peakrdl_toml"
]

py_library(
    name = "peakrdl",
    deps = [
        "@pip_deps//peakrdl",
    ] + PLUGINS,
)

system_rdl_toolchain(
    name = "system_rdl_toolchain",
    peakrdl = ":peakrdl",
    peakrdl_config = "peakrdl.toml",
    exporter_files = {
        "regblock": ".sv,_pkg.sv",
        "toml": ".toml",
    },
    exporter_dirs = {
        "html": "_html",
    },
)

toolchain(
    name = "toolchain",
    toolchain = ":system_rdl_toolchain",
    toolchain_type = "@rules_systemrdl//systemrdl:toolchain_type",
    visibility = ["//visibility:public"],
)
```

`peakrdl.toml`:
```toml
# https://peakrdl.readthedocs.io/en/latest/configuring.html
[peakrdl]
# The import path should be the repo realtive import path of the plugin.
plugins.exporters.toml = "tools.system_rdl.peakrdl_toml:TomlExporter"
```

Now with the toolchain configured. all `system_rdl_library` targets built
in the same configuration as the registered toolchain will have an additional
output group `system_rdl_toml` that is the output of the custom exporter.

""",
    implementation = _system_rdl_toolchain_impl,
    attrs = {
        "exporter_args": attr.string_list_dict(
            doc = "A pair of `exporters` keys to a list of default exporter args to apply to all rules.",
        ),
        "exporter_dirs": attr.string_dict(
            doc = "A mapping of exporters to expected output directories formats.",
            default = {
                "html": "_html",
            },
            allow_empty = False,
        ),
        "exporter_files": attr.string_dict(
            doc = "A mapping of exporters to expected output file formats.",
            default = {
                "regblock": ".sv,_pkg.sv",
            },
            allow_empty = False,
        ),
        "peakrdl": attr.label(
            doc = "The python library for the `peakrdl` package.",
            cfg = "exec",
            providers = [PyInfo],
        ),
        "peakrdl_config": attr.label(
            doc = "The `peakrdl` config file.",
            allow_single_file = [".toml"],
            mandatory = True,
        ),
    },
)

def _system_rdl_peakrdl_toolchain_alias_impl(ctx):
    toolchain = ctx.toolchains[TOOLCHAIN_TYPE]
    target = toolchain.peakrdl

    # For some reason, simply forwarding `DefaultInfo` from
    # the target results in a loss of data. To avoid this a
    # new provider is created with the same info.
    default_info = DefaultInfo(
        files = target[DefaultInfo].files,
        runfiles = target[DefaultInfo].default_runfiles,
    )

    return [
        default_info,
        target[PyInfo],
        target[OutputGroupInfo],
        target[InstrumentedFilesInfo],
    ]

system_rdl_peakrdl_toolchain_alias = rule(
    doc = "Access the registered `system_rdl_toolchain` for the current configuration.",
    implementation = _system_rdl_peakrdl_toolchain_alias_impl,
    toolchains = [TOOLCHAIN_TYPE],
)

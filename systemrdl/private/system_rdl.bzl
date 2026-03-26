"""SystemRDL Bazel rules"""

load("@rules_venv//python:py_info.bzl", "PyInfo")

TOOLCHAIN_TYPE = str(Label("//systemrdl:toolchain_type"))

SystemRdlInfo = provider(
    doc = "Info for SystemRDL targets.",
    fields = {
        "root": "File: The top level source file for a library.",
        "srcs": "Depset[File]: All (including transitive) source files.",
    },
)

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

    outputs = {}
    output_groups = {}
    for exporter in ctx.attr.exporter_args:
        if exporter not in toolchain.exporters:
            fail("Unsupported exporter command '{}'. Please update `{}` to use one of `{}`".format(
                exporter,
                ctx.label,
                sorted(toolchain.exporters.keys()),
            ))

    for exporter, extension in toolchain.exporters.items():
        name = "{}{}".format(ctx.label.name, extension)

        if extension.startswith("."):
            output = ctx.actions.declare_file(name)
            output_path = output.dirname
        else:
            output = ctx.actions.declare_directory(name)
            output_path = output.path

        outputs[exporter] = output

        args = ctx.actions.args()
        args.add("--peakrdl-cfg", toolchain.peakrdl_config)
        args.add(exporter)
        args.add_all(srcs)
        args.add_all(toolchain.default_exporter_args.get(exporter, []))
        args.add_all(ctx.attr.exporter_args.get(exporter, []))
        args.add("-o", output_path)

        ctx.actions.run(
            mnemonic = "SystemRdl{}".format(exporter.capitalize()),
            outputs = [output],
            executable = ctx.executable._peakrdl,
            arguments = [args],
            inputs = srcs,
            tools = [toolchain.peakrdl_config],
        )

        output_groups["system_rdl_{}".format(exporter)] = depset([output])

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

def _system_rdl_toolchain_impl(ctx):
    for exporter in ctx.attr.exporters:
        if " " in exporter:
            fail("`{}` has an exporter with an illegal name: `{}`".format(
                ctx.label,
                exporter,
            ))

    for key in ctx.attr.exporter_args:
        if key not in ctx.attr.exporters:
            fail("Args were given for `{}` but it's not a known exporter `{}`. Please update `{}`".format(
                key,
                sorted(ctx.attr.exporters.keys()),
                ctx.label,
            ))

    return [
        platform_common.ToolchainInfo(
            exporters = ctx.attr.exporters,
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
load("//systemrdl:system_rdl_toolchain.bzl", "system_rdl_toolchain")

py_library(
    name = "peakrdl_toml",
    srcs = ["peakrdl_toml.py"],
    deps = [
        "@pip_deps//peakrdl",
        "@pip_deps//tomli",
    ],
)

PLUGINS = [
    ":peakrdl_toml
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
    exporters = {
        "html": "_html",
        "regblock": ".sv",
        "toml": ".toml",
    },
)

toolchain(
    name = "toolchain",
    toolchain = ":system_rdl_toolchain",
    toolchain_type = "@rules_verilog//systemrdl:toolchain_type",
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
        "exporters": attr.string_dict(
            doc = "A mapping of exporters to expected output file formats.",
            default = {
                "html": "_html",
                "regblock": ".sv",
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

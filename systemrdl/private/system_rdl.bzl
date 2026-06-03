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

_NAME_PLACEHOLDER = "{name}"

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

def _parse_output_descriptor(exporter, entry, kind):
    """Parse a single `<id>=<pattern>` descriptor.

    `kind` is supplied by the caller based on which toolchain attribute the
    entry came from (`exporter_files` → file, `exporter_dirs` → dir).
    Returns a struct(id, kind, pattern). Fails on anything malformed.
    """
    if "=" not in entry:
        fail((
            "Exporter `{exporter}` has a malformed output descriptor `{entry}`. " +
            "Expected `<id>=<pattern>`, e.g. `sv={{name}}.sv` or " +
            "`utils=regblock_pkg.vhdl`."
        ).format(exporter = exporter, entry = entry))
    id, _, pattern = entry.partition("=")
    if not id:
        fail("Exporter `{}` has an output descriptor with an empty id: `{}`".format(
            exporter,
            entry,
        ))
    for ch in id.elems():
        if not (ch.isalnum() or ch == "_"):
            fail((
                "Exporter `{exporter}` has an output id `{id}` containing " +
                "an illegal character `{ch}`. Ids must match [A-Za-z0-9_]."
            ).format(exporter = exporter, id = id, ch = ch))
    if not pattern:
        fail("Exporter `{}` has output descriptor `{}` with an empty pattern".format(
            exporter,
            entry,
        ))
    return struct(id = id, kind = kind, pattern = pattern)

def _parse_exporter_outputs(exporter_files, exporter_dirs):
    """Parse the toolchain's `exporter_files` and `exporter_dirs` attributes.

    Returns Dict[exporter_name, List[struct(id, kind, pattern)]] where kind
    is "file" or "dir" depending on which attribute the entries came from.
    Validates that an exporter is not registered under both attributes and
    that ids are unique within each exporter.
    """
    parsed = {}
    for source_dict, kind in [(exporter_files, "file"), (exporter_dirs, "dir")]:
        for exporter, entries in source_dict.items():
            if " " in exporter:
                fail("Exporter name `{}` is illegal (no whitespace allowed)".format(exporter))
            if exporter in parsed:
                fail((
                    "Exporter `{exporter}` is registered in both " +
                    "`exporter_files` and `exporter_dirs`. An exporter " +
                    "produces either files or a directory; pick one."
                ).format(exporter = exporter))
            if not entries:
                fail("Exporter `{}` has no output descriptors".format(exporter))
            descriptors = []
            seen_ids = {}
            for entry in entries:
                desc = _parse_output_descriptor(exporter, entry, kind)
                if desc.id in seen_ids:
                    fail((
                        "Exporter `{exporter}` declares output id `{id}` " +
                        "twice (entries: `{prev}` and `{cur}`). Each id " +
                        "within an exporter must be unique."
                    ).format(
                        exporter = exporter,
                        id = desc.id,
                        prev = seen_ids[desc.id],
                        cur = entry,
                    ))
                seen_ids[desc.id] = entry
                descriptors.append(desc)
            parsed[exporter] = descriptors
    return parsed

def _render_pattern(pattern, output_name):
    """Substitute the resolved output_name into a descriptor pattern."""
    return pattern.replace(_NAME_PLACEHOLDER, output_name)

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
    known_exporters = sorted(toolchain.exporter_outputs.keys())

    for exporter in ctx.attr.exporter_args:
        if exporter not in toolchain.exporter_outputs:
            fail("Unsupported exporter command '{}'. Please update `{}` to use one of `{}`".format(
                exporter,
                ctx.label,
                known_exporters,
            ))

    rename_values = {}
    for exporter, exporter_args in ctx.attr.exporter_args.items():
        rename = _extract_rename(exporter_args)
        if rename != None:
            rename_values[exporter] = rename

    exporter_outs = {}
    output_groups = {}
    for exporter, descriptors in toolchain.exporter_outputs.items():
        rename = rename_values.get(exporter)
        if rename != None:
            output_name = rename
        elif ctx.attr.output_name:
            output_name = ctx.attr.output_name
        else:
            output_name = ctx.label.name

        output_group_prefix = "system_rdl_{}".format(exporter)
        all_outputs = []
        file_outputs = []
        dir_outputs = []
        for desc in descriptors:
            rendered = _render_pattern(desc.pattern, output_name)
            if desc.kind == "file":
                output = ctx.actions.declare_file(rendered)
                file_outputs.append(output)
            else:
                output = ctx.actions.declare_directory(rendered)
                dir_outputs.append(output)
            all_outputs.append(output)
            output_groups["{}_{}".format(output_group_prefix, desc.id)] = depset([output])

        args = ctx.actions.args()
        args.add_joined("--bazel-outputs", all_outputs, join_with = ",", expand_directories = False)
        args.add("--")
        args.add("--peakrdl-cfg", toolchain.peakrdl_config)
        args.add(exporter)
        args.add_all(srcs)
        args.add_all(toolchain.default_exporter_args.get(exporter, []))
        args.add_all(ctx.attr.exporter_args.get(exporter, []))

        # peakrdl takes a single `-o` per invocation pointing at an output
        # location. For file outputs we hand it the directory the declared
        # files live in; for directory outputs we hand it the declared
        # directory path directly. Mixing the two within one exporter is not
        # supported and shouldn't arise in practice.
        if file_outputs and dir_outputs:
            fail((
                "Exporter `{exporter}` declares both file and directory " +
                "outputs in the same invocation, which peakrdl does not " +
                "support. Split them across separate exporter registrations."
            ).format(exporter = exporter))
        if file_outputs:
            args.add_all(
                file_outputs,
                before_each = "-o",
                expand_directories = False,
                uniquify = True,
                map_each = _dirname_map,
            )
        else:
            args.add_all(
                dir_outputs,
                before_each = "-o",
                expand_directories = False,
                uniquify = True,
            )

        mnemonic_suffix = "".join([
            part.capitalize()
            for part in exporter.replace("_", "-").split("-")
        ])
        ctx.actions.run(
            mnemonic = "SystemRdl{}".format(mnemonic_suffix),
            outputs = all_outputs,
            executable = ctx.executable._peakrdl,
            arguments = [args],
            inputs = srcs,
            tools = [toolchain.peakrdl_config],
            execution_requirements = {"supports-path-mapping": ""},
        )

        output_set = depset(all_outputs)
        exporter_outs[exporter] = output_set
        output_groups[output_group_prefix] = output_set

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
    exporter_outputs = _parse_exporter_outputs(
        ctx.attr.exporter_files,
        ctx.attr.exporter_dirs,
    )

    known_exporters = sorted(exporter_outputs.keys())
    for key in ctx.attr.exporter_args:
        if key not in exporter_outputs:
            fail("Args were given for `{}` but it's not a known exporter `{}`. Please update `{}`".format(
                key,
                known_exporters,
                ctx.label,
            ))

    return [
        platform_common.ToolchainInfo(
            exporter_outputs = exporter_outputs,
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
        "regblock": [
            "sv={name}.sv",
            "pkg={name}_pkg.sv",
        ],
        "toml": [
            "toml={name}.toml",
        ],
    },
    exporter_dirs = {
        "html": [
            "dir={name}_html",
        ],
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

## Describing exporter outputs

Each exporter is registered with a list of output descriptors of the form
`<id>=<pattern>`. Exporters that produce regular files go in
`exporter_files`; exporters that produce a directory go in `exporter_dirs`
(an exporter cannot be registered in both).

- `<id>` is a stable identifier used to address this specific output from
  downstream consumers (e.g. the `system_rdl_<exporter>_<id>` output group,
  or the `extract` attribute on `verilog_system_rdl_library` /
  `vhdl_system_rdl_library`). Ids must be unique within an exporter and
  match `[A-Za-z0-9_]+`.
- `<pattern>` is the basename of the output. The literal token `{name}` is
  expanded to the target's resolved output name (target name, the
  `output_name` attribute, or `--rename`). Patterns without `{name}` are
  fixed-name outputs the exporter always writes under that exact basename
  (e.g. a shared utility package emitted by
  `peakrdl regblock-vhdl --copy-utils-pkg`).
""",
    implementation = _system_rdl_toolchain_impl,
    attrs = {
        "exporter_args": attr.string_list_dict(
            doc = "A pair of `exporters` keys to a list of default exporter args to apply to all rules.",
        ),
        "exporter_dirs": attr.string_list_dict(
            doc = (
                "A mapping of exporter name to a list of output " +
                "descriptors `<id>=<pattern>` for exporters that produce " +
                "a directory. See the rule's main documentation for the " +
                "descriptor format."
            ),
            default = {
                "html": ["dir={name}_html"],
            },
        ),
        "exporter_files": attr.string_list_dict(
            doc = (
                "A mapping of exporter name to a list of output " +
                "descriptors `<id>=<pattern>` for exporters that produce " +
                "regular files. See the rule's main documentation for the " +
                "descriptor format."
            ),
            default = {
                "regblock": ["sv={name}.sv", "pkg={name}_pkg.sv"],
            },
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

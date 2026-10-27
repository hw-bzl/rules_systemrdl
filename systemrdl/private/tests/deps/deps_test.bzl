"""Analysis tests for `system_rdl_library` source ordering across `deps`."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//systemrdl:system_rdl_info.bzl", "SystemRdlInfo")

# Dependencies first (leaf before the mids that instantiate it), then the
# library's own non-root sources, then the root last.
_EXPECTED_ORDER = [
    "leaf.rdl",
    "mid_a.rdl",
    "mid_b.rdl",
    "top_types.rdl",
    "top.rdl",
]

def _basenames(files):
    return [f.basename for f in files]

def _rdl_args(action):
    return [arg for arg in action.argv if arg.endswith(".rdl")]

def _source_order_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    info = target[SystemRdlInfo]
    asserts.equals(
        env,
        "top.rdl",
        info.root.basename,
        "`SystemRdlInfo.root` should be the library's top-level source",
    )
    asserts.equals(
        env,
        _EXPECTED_ORDER,
        _basenames(info.srcs.to_list()),
        "`SystemRdlInfo.srcs` must list transitive deps first and the root last",
    )
    asserts.equals(
        env,
        _EXPECTED_ORDER,
        _basenames(target[DefaultInfo].files.to_list()),
        "`DefaultInfo.files` must list transitive deps first and the root last",
    )

    # Every exporter action receives the same source list, in the same order.
    rdl_actions = [
        action
        for action in analysistest.target_actions(env)
        if action.mnemonic.startswith("SystemRdl")
    ]
    asserts.true(env, len(rdl_actions) > 0, "Expected at least one SystemRdl* action")
    for action in rdl_actions:
        asserts.equals(
            env,
            _EXPECTED_ORDER,
            [arg.rpartition("/")[2] for arg in _rdl_args(action)],
            "Action `{}` must pass `.rdl` inputs to peakrdl with deps first and the root last".format(
                action.mnemonic,
            ),
        )

        # The root must come after the `<exporter>` subcommand and before any
        # exporter args, i.e. the `.rdl` arguments must be contiguous.
        argv = list(action.argv)
        rdl_indices = [i for i, arg in enumerate(argv) if arg.endswith(".rdl")]
        asserts.equals(
            env,
            rdl_indices,
            list(range(rdl_indices[0], rdl_indices[0] + len(rdl_indices))),
            "`.rdl` arguments for `{}` must be contiguous: `{}`".format(action.mnemonic, argv),
        )

    return analysistest.end(env)

source_order_test = analysistest.make(_source_order_test_impl)

def _diamond_dedup_test_impl(ctx):
    """`leaf.rdl` is reachable via both `mid_a` and `mid_b` but must appear once."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    srcs = _basenames(target[SystemRdlInfo].srcs.to_list())
    asserts.equals(
        env,
        1,
        len([src for src in srcs if src == "leaf.rdl"]),
        "Diamond dependency `leaf.rdl` should be de-duplicated, got `{}`".format(srcs),
    )

    for action in analysistest.target_actions(env):
        if not action.mnemonic.startswith("SystemRdl"):
            continue
        rdl_args = _rdl_args(action)
        asserts.equals(
            env,
            len(rdl_args),
            len({arg: None for arg in rdl_args}),
            "Action `{}` passed a duplicate `.rdl` to peakrdl: `{}`".format(action.mnemonic, rdl_args),
        )

    return analysistest.end(env)

diamond_dedup_test = analysistest.make(_diamond_dedup_test_impl)

def _intermediate_order_test_impl(ctx):
    """A single-dep library must still emit the dep before its own root."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.equals(
        env,
        ["leaf.rdl", "mid_a.rdl"],
        _basenames(target[SystemRdlInfo].srcs.to_list()),
        "A direct dependency must precede the dependent library's root",
    )

    return analysistest.end(env)

intermediate_order_test = analysistest.make(_intermediate_order_test_impl)

def deps_test_suite(*, name, top, mid_a = None, **kwargs):
    """Entry point for the `deps` ordering analysis tests.

    Args:
        name: The name of the generated `test_suite`.
        top: Label of the `top` `system_rdl_library` under test.
        mid_a: Optional label of the `mid_a` `system_rdl_library` under test.
        **kwargs: Additional keyword arguments forwarded to `test_suite`.
    """
    tests = []

    source_order_test(
        name = name + "_source_order_test",
        target_under_test = top,
    )
    tests.append(name + "_source_order_test")

    diamond_dedup_test(
        name = name + "_diamond_dedup_test",
        target_under_test = top,
    )
    tests.append(name + "_diamond_dedup_test")

    if mid_a:
        intermediate_order_test(
            name = name + "_mid_a_order_test",
            target_under_test = mid_a,
        )
        tests.append(name + "_mid_a_order_test")

    native.test_suite(
        name = name,
        tests = tests,
        **kwargs
    )

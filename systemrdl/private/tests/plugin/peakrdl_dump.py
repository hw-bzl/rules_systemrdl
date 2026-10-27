"""A minimal PeakRDL exporter plugin that lists register addresses and names."""

import argparse
import os

from peakrdl.plugins.exporter import ExporterSubcommandPlugin
from systemrdl.node import AddrmapNode, RegNode


class ReglistExporter(ExporterSubcommandPlugin):
    """Write one line per register: ``0x<absolute_address> <path.from.top>``.

    Registers are listed recursively (nested addrmaps / regfiles included) so
    the dump reflects the full elaborated hierarchy under ``top_node``.
    """

    short_desc: str = "List register addresses and names to text"

    def do_export(self, top_node: AddrmapNode, options: argparse.Namespace) -> None:
        path: str = os.path.join(options.output, top_node.inst_name + ".txt")
        with open(path, "w", encoding="utf-8") as f:
            for node in top_node.descendants():
                if not isinstance(node, RegNode):
                    continue
                f.write(f"0x{node.absolute_address:x} {node.get_rel_path(top_node)}\n")

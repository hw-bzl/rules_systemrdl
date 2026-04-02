"""A minimal PeakRDL exporter plugin that lists register addresses and names."""

import argparse
import os

from peakrdl.plugins.exporter import ExporterSubcommandPlugin
from systemrdl.node import AddrmapNode


class ReglistExporter(ExporterSubcommandPlugin):
    short_desc: str = "List register addresses and names to text"

    def do_export(self, top_node: AddrmapNode, options: argparse.Namespace) -> None:
        path: str = os.path.join(options.output, top_node.inst_name + ".txt")
        with open(path, "w") as f:
            for reg in top_node.registers():
                f.write("0x{:x} {}\n".format(reg.address_offset, reg.inst_name))

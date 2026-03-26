"""A minimal PeakRDL exporter plugin that lists register addresses and names."""

import os

from peakrdl.plugins.exporter import ExporterSubcommandPlugin


class ReglistExporter(ExporterSubcommandPlugin):
    short_desc = "List register addresses and names to text"

    def do_export(self, top_node, options):
        path = os.path.join(options.output, top_node.inst_name + ".txt")
        with open(path, "w") as f:
            for reg in top_node.registers():
                f.write("0x{:x} {}\n".format(reg.address_offset, reg.inst_name))

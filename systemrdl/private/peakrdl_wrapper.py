"""The PeakRDL Bazel entrypoint for use in system_rdl rules."""

from peakrdl.main import main as peakrdl_main

if __name__ == "__main__":
    peakrdl_main()

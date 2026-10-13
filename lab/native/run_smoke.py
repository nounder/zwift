"""Launch the Zig App, validate its runtime checks, and audit its Mach-O inputs."""
import os
import pathlib
import subprocess
import sys


def verify(binary):
    binary = pathlib.Path(binary).resolve()
    for mode in ("metadata", "launch"):
        result = subprocess.run([str(binary)], env=dict(os.environ, ZWIFT_NATIVE_PROBE=mode),
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print(f"Native runtime mode: {mode}\n{output}", end="")
        if result.returncode or "NATIVE_ABI_OK:" not in output:
            raise SystemExit(f"Native runtime probe failed ({mode}): exit {result.returncode}")
        for example, marker in (("Animations", "ANIMATION_ABI_OK:"), ("Paint", "PAINT_ABI_OK:")):
            if binary.name == f"Zwift{example}" and marker not in output:
                raise SystemExit(f"{example} integration checks did not complete")
        if mode == "metadata" and "NATIVE_ABI_METADATA_OK:" not in output:
            raise SystemExit("Native metadata verification did not complete")
    dependencies = subprocess.check_output(["otool", "-L", str(binary)], text=True)
    for name in ("SwiftUI.framework", "libswiftCore.dylib"):
        if name not in dependencies:
            raise SystemExit(f"Missing required runtime dependency: {name}")
    symbols = subprocess.check_output(["nm", "-u", str(binary)], text=True)
    if "_$s7SwiftUI3AppPAAE4mainyyFZ" not in symbols:
        raise SystemExit("Executable does not call SwiftUI App.main")
    sections = subprocess.check_output(["otool", "-l", str(binary)], text=True)
    for name in ("__swift5_types", "__swift5_proto", "__swift5_fieldmd", "__swift5_entry", "__objc_imageinfo"):
        if name not in sections:
            raise SystemExit(f"Missing Swift runtime section: {name}")
    print("NATIVE_MACHO_OK: App.main, SwiftUI/runtime dependencies, type/conformance/image sections")


if __name__ == "__main__":
    verify(sys.argv[1])

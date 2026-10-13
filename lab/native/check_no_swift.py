"""Cold-build and launch under a macOS sandbox that denies Swift compilers.

Both Zig caches and the install prefix are fresh. Compiler/SDK installation is
left untouched. No generated/precompiled Swift application object is an input.
"""
import os
import pathlib
import shlex
import subprocess
import sys
import tempfile

zig, optimize = pathlib.Path(sys.argv[1]).resolve(), sys.argv[2]
root = pathlib.Path(__file__).resolve().parents[2]
profile = '(version 1)(allow default)(deny process-exec (regex #"/swift(c|-frontend)?$"))'
sandbox = ["/usr/bin/sandbox-exec", "-p", profile]

with tempfile.TemporaryDirectory(prefix="zwift-no-swift-") as temporary:
    temporary = pathlib.Path(temporary)
    # Verify the deny rule using a harmless executable, without needing swiftc.
    forbidden = temporary / "swiftc"
    forbidden.write_text("#!/bin/sh\nexit 0\n")
    forbidden.chmod(0o755)
    rejected = subprocess.run([*sandbox, str(forbidden)], capture_output=True, text=True)
    if rejected.returncode == 0 or "Operation not permitted" not in rejected.stderr:
        raise SystemExit(f"Swift compiler execution guard is ineffective: {rejected.stderr}")
    prefix = temporary / "out"
    command = [str(zig), "build", "lab-native-examples", f"-Doptimize={optimize}",
               "--cache-dir", str(temporary / "cache"), "--global-cache-dir", str(temporary / "global"),
               "--prefix", str(prefix), "--verbose", "--summary", "all"]
    result = subprocess.run([*sandbox, *command], cwd=root, capture_output=True, text=True, timeout=240)
    output = result.stdout + result.stderr
    # Keep the build trace, including every application compiler/linker input.
    reports = root / "zig-out/lab/native"
    reports.mkdir(parents=True, exist_ok=True)
    (reports / f"no-swift-{optimize}.log").write_text(output)
    if result.returncode:
        print(output)
        raise SystemExit(f"Cold build with Swift compilation denied failed: {result.returncode}")
    compiles = [shlex.split(line) for line in output.splitlines() if " build-exe " in line]
    if len(compiles) != 3:
        raise SystemExit(f"Expected three native application compiles; found {len(compiles)}")
    for args in compiles:
        if not any(arg.endswith("/lab/native/main.zig") for arg in args):
            raise SystemExit("Unexpected application root module")
        for arg in args:
            if arg.endswith((".swift", ".o", ".a", ".dylib")):
                raise SystemExit(f"Unexpected source/precompiled object input: {arg}")
    for name in ("Native", "Animations", "Paint"):
        binary = prefix / f"Zwift{name}.app/Contents/MacOS/Zwift{name}"
        # Runtime checks also run with all Swift compiler executables denied.
        smoke = subprocess.run([*sandbox, sys.executable, str(pathlib.Path(__file__).with_name("run_smoke.py")), str(binary)],
                               env=os.environ.copy(), capture_output=True, text=True, timeout=40)
        print(smoke.stdout + smoke.stderr, end="")
        with (reports / f"no-swift-{optimize}.log").open("a") as report:
            report.write(smoke.stdout + smoke.stderr)
        smoke.check_returncode()
    print(f"NO_SWIFTC_OK: {optimize}, Native + Animations + Paint, fresh local/global caches, no Swift/application object inputs, guarded build and launch")

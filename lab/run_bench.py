"""Keep a machine-readable result and print a short, reproducible timing table."""
import json
import pathlib
import subprocess
import sys

exe, destination = sys.argv[1:]
result = subprocess.run([exe], check=True, capture_output=True, text=True, timeout=180)
report = json.loads(result.stdout)
report["machine"] = subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
report["swift"] = subprocess.check_output(["swiftc", "--version"], text=True, stderr=subprocess.STDOUT).strip()
report["zig"] = "0.16.0 ReleaseFast"
path = pathlib.Path(destination)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(report, indent=2) + "\n")
for row in report["results"]:
    print(f"{row['name']:42s} {row['median_ns']:12.1f} ns/op")
print(f"Performance report: {path}")
if result.stderr:
    print(result.stderr, file=sys.stderr)

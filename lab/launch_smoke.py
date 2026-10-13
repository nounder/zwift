"""Exercise each real Swift @main App, including AppKit window creation."""
import os
import pathlib
import subprocess
import sys

prefix = pathlib.Path(sys.argv[1]).resolve()
output = prefix / "lab" / "screenshots"
output.mkdir(parents=True, exist_ok=True)
for name in ("Todo", "Editor", "Browser"):
    binary = prefix / f"Zwift{name}.app/Contents/MacOS/Zwift{name}"
    png = output / f"{name.lower()}-app.png"
    env = dict(os.environ, ZWIFT_LAUNCH_PROBE=str(png))
    subprocess.run([str(binary)], env=env, check=True, timeout=20)
    assert png.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"), png

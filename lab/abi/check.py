"""Check every registered specialization against independently lowered Swift code."""
import json
import pathlib
import re
import subprocess
import sys
import tempfile

generated = pathlib.Path(sys.argv[1])
manifest = json.loads((generated / "ABIManifest.json").read_text())
with tempfile.TemporaryDirectory(prefix="zwift-abi-") as tmp:
    ir = pathlib.Path(tmp) / "oracle.ll"
    subprocess.run(["swiftc", "-target", manifest["target"], "-parse-as-library",
                    "-whole-module-optimization", "-emit-ir", "-Onone",
                    str(generated / "NativeABI.swift"), str(generated / "ABIReferences.swift"),
                    "-o", str(ir)], check=True)
    text = ir.read_text()
    for spec in manifest["specializations"]:
        symbol = "oracle_" + spec["symbol"]
        match = re.search(r'define swiftcc (.*?) @' + re.escape(symbol) + r'\((.*?)\)', text)
        if not match:
            raise SystemExit(f"ABI CHECK FAILED: missing Swift definition {symbol}")
        actual_args = ",".join(arg.strip().split()[0] for arg in match[2].split(","))
        if match[1] != spec["result"] or actual_args != spec["arguments"]:
            raise SystemExit(f"ABI CHECK FAILED: {symbol}: {match[1]} ({actual_args}) != {spec['result']} ({spec['arguments']})")
        print(f"Swift IR verified: {spec['type']} ({spec['symbol']})")
    signatures = {
        "State.init": r'declare swiftcc void @"\$s7SwiftUI5StateV12wrappedValueACyxGx_tcfC"\(ptr noalias sret\(%swift.opaque\), ptr noalias, ptr\)',
        "Environment.init": r'declare swiftcc void @"\$s7SwiftUI11EnvironmentVyACyxGs7KeyPathCyAA0C6ValuesVxGcfC"\(ptr noalias sret\(%swift.opaque\), ptr\)',
        "Binding.constant": r'declare swiftcc void @"\$s7SwiftUI7BindingV8constantyACyxGxFZ"\(ptr noalias sret\(%swift.opaque\), ptr noalias, ptr\)',
        "Text.init": r'declare swiftcc \{ i64, i64, i8, ptr \} @"\$s7SwiftUI4TextV8verbatimACSS_tcfC"\(i64, ptr\)',
    }
    for name, pattern in signatures.items():
        if not re.search(pattern, text):
            raise SystemExit(f"ABI CHECK FAILED: {name}; inspect compiler lowering")
        print(f"Swift IR verified: {name}")

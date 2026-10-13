"""Check the native backend's ABI assumptions against the installed swiftc.

An optional development check, completely outside lab-native's dependency graph.
It checks contracts, not exact compiler instruction sequences.
"""
import pathlib
import re
import subprocess
import sys
import tempfile

target = sys.argv[1]
with tempfile.TemporaryDirectory(prefix="zwift-native-oracle-") as temporary:
    ir = pathlib.Path(temporary) / "oracle.ll"
    subprocess.run([
        "swiftc", "-target", target, "-parse-as-library", "-module-name", "ZwiftNative",
        "-Onone", "-emit-ir", str(pathlib.Path(__file__).with_name("oracle.swift")),
        "-o", str(ir),
    ], check=True)
    text = ir.read_text()
    signatures = {
        "App.main (including Swift self register)": r'declare swiftcc void @"\$s7SwiftUI3AppPAAE4mainyyFZ"\(ptr, ptr, ptr swiftself\)',
        "WindowGroup metadata": r'declare swiftcc %swift.metadata_response @"\$s7SwiftUI11WindowGroupVMa"\(i64, ptr, ptr\)',
        "WindowGroup initializer (10 arguments + indirect result)": r'declare swiftcc void @"\$s7SwiftUI11WindowGroupV2id5title11lazyContentACyxGSSSg_AA4TextVSgxyctcfC"\(ptr noalias sret\(%swift.opaque\), i64, i64, i64, i64, i64, i64, ptr, ptr, ptr, ptr\)',
        "Text initializer": r'declare swiftcc \{ i64, i64, i8, ptr \} @"\$s7SwiftUI4TextV8verbatimACSS_tcfC"\(i64, ptr\)',
        "View.body witness indirect result": r'define internal swiftcc void @"\$s11ZwiftNative7ZigRootV[^"\n]+4body4BodyQzvgTW"\(ptr noalias nocapture sret\(%T7SwiftUI4TextV\)',
        "App.body witness indirect result": r'define internal swiftcc void @"\$s11ZwiftNative6ZigAppV[^"\n]+4body4BodyQzvgTW"\(ptr noalias sret\(%swift.opaque\)',
    }
    for name, pattern in signatures.items():
        if not re.search(pattern, text):
            raise SystemExit(f"Native ABI oracle mismatch: {name}; inspect the new lowering")
        print(f"Native ABI oracle verified: {name}")
    for name, count in (("7ZigRoot", 6), ("6ZigApp", 4)):
        descriptor = re.search(r'^@"\$s11ZwiftNative' + name + r'V[^"\n]+AAMc" = hidden constant.*$', text, re.M)
        if not descriptor or f"i32 0, i32 196608, i32 {count}," not in descriptor[0]:
            raise SystemExit(f"Native ABI oracle mismatch: {name} resilient conformance")
        if "i16 0, i16 1, i32 0," not in descriptor[0]:
            raise SystemExit(f"Native ABI oracle mismatch: {name} witness cache")
        print(f"Native ABI oracle verified: {name} resilient conformance ({count} requirements)")
    for name in ("7ZigRoot", "6ZigApp"):
        metadata = re.search(r'^@"\$s11ZwiftNative' + name + r'VMf" = .*$', text, re.M)
        if not metadata or 'ptr @"$sytWV", i64 512,' not in metadata[0]:
            raise SystemExit(f"Native ABI oracle mismatch: {name} empty struct metadata/value witnesses")
    print("Native ABI oracle verified: both empty struct layouts share the empty-tuple value witnesses")

    for fixture in ("Animation", "Paint"):
        output = pathlib.Path(temporary) / f"{fixture}.ll"
        subprocess.run([
            "swiftc", "-target", target, "-parse-as-library", "-module-name", f"{fixture}Oracle",
            "-Onone", "-emit-ir", "-suppress-warnings",
            str(pathlib.Path(__file__).with_name("oracle") / f"{fixture}.swift"), "-o", str(output),
        ], check=True)
        text = output.read_text()
        if fixture == "Animation":
            signatures = {
                "TimelineView initializer": r'declare swiftcc void @"\$s7SwiftUI12TimelineViewVA2A0D0R_rlE_7contentACyxq_Gx_q_AC7ContextVyxq__GctcfC"\(ptr noalias sret\(%swift.opaque\), ptr noalias, ptr, ptr, ptr, ptr, ptr, ptr\)',
                "animation schedule optional Double": r'declare swiftcc void @"\$s7SwiftUI25AnimationTimelineScheduleV15minimumInterval6pausedACSdSg_SbtcfC"\(ptr noalias sret\(%swift.opaque\), i64, i8, i1\)',
                "Canvas renderer closure": r'declare swiftcc void @"\$s7SwiftUI6CanvasVA2A9EmptyViewVRszrlE6opaque9colorMode21rendersAsynchronously8rendererACyAEGSb_AA014ColorRenderingH0OSbyAA15GraphicsContextVz_So6CGSizeVtctcfC"\(ptr noalias sret\(%swift.opaque\), i1, ptr noalias, i1, ptr, ptr\)',
                "withCGContext throwing closure ABI": r'declare swiftcc void @"\$s7SwiftUI15GraphicsContextV13withCGContext7contentyySo0F3RefaKXE_tKF"\(ptr, ptr, ptr, ptr swiftself, ptr noalias nocapture swifterror dereferenceable\(8\)\)',
            }
        else:
            signatures = {
                "makeNSView owned pointer result": r'define internal swiftcc ptr @"[^"\n]+04makeF07context[^"\n]+TW"\(ptr noalias %0, ptr noalias nocapture swiftself %1, ptr %Self, ptr %SelfWitnessTable\)',
                "updateNSView view argument": r'define internal swiftcc void @"[^"\n]+06updateF0_[^"\n]+TW"\(ptr %0, ptr noalias %1, ptr noalias nocapture swiftself %2, ptr %Self, ptr %SelfWitnessTable\)',
                "dismantleNSView view argument": r'define internal swiftcc void @"[^"\n]+09dismantleF0_[^"\n]+TW"\(ptr %0, ptr noalias nocapture %1, ptr swiftself %2, ptr %Self, ptr %SelfWitnessTable\)',
                "sizeThatFits optional CGSize lowering": r'define internal swiftcc \{ i64, i64, i8 \} @"[^"\n]+12sizeThatFits[^"\n]+TW"\(i64 %0, i8 %1, i64 %2, i8 %3,',
            }
            descriptor = re.search(r'^@"[^"\n]+NSViewRepresentableAAMc" = hidden constant.*$', text, re.M)
            if not descriptor or "i32 0, i32 196608, i32 14," not in descriptor[0]:
                raise SystemExit("Native ABI oracle mismatch: NSViewRepresentable resilient requirements")
            print("Native ABI oracle verified: NSViewRepresentable resilient conformance (14 requirements)")
        for name, pattern in signatures.items():
            if not re.search(pattern, text):
                raise SystemExit(f"Native ABI oracle mismatch: {name}; inspect the new lowering")
            print(f"Native ABI oracle verified: {name}")

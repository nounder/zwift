const std = @import("std");
const platform = @import("platform.zig");
pub fn add(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .aarch64, .os_tag = .macos, .os_version_min = .{ .semver = platform.minimum_macos } });
    const sdk = std.mem.trim(u8, b.run(&.{ "xcrun", "--show-sdk-path" }), &std.ascii.whitespace);
    const native_all = b.step("lab-native-examples", "Build Native, Animations and Paint without swiftc");
    const native_test_all = b.step("lab-native-examples-test", "Test all native Swift ABI examples and their Zig models");
    inline for (.{ "Native", "Animations", "Paint" }) |name| {
        const step_name = if (comptime std.mem.eql(u8, name, "Native")) "native" else name;
        const native = b.addExecutable(.{ .name = "Zwift" ++ name, .root_module = b.createModule(.{
            .root_source_file = b.path("lab/native/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }) });
        const options = b.addOptions();
        options.addOption([]const u8, "example", name);
        native.root_module.addOptions("options", options);
        native.root_module.addImport("objc", b.createModule(.{ .root_source_file = b.path("src/objc.zig"), .target = target, .optimize = optimize }));
        native.root_module.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/usr/lib", .{sdk}) });
        native.root_module.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/usr/lib/swift", .{sdk}) });
        native.root_module.addFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{sdk}) });
        native.root_module.addRPath(.{ .cwd_relative = "/usr/lib/swift" });
        native.root_module.linkSystemLibrary("swiftCore", .{});
        native.root_module.linkSystemLibrary("objc", .{});
        for ([_][]const u8{ "SwiftUI", "SwiftUICore", "AppKit", "Foundation", "CoreGraphics", "QuartzCore" }) |framework| native.root_module.linkFramework(framework, .{});
        const native_install = b.addInstallFile(native.getEmittedBin(), "Zwift" ++ name ++ ".app/Contents/MacOS/Zwift" ++ name);
        const native_files = b.addWriteFiles();
        const native_asm = b.addInstallFile(native_files.add(name ++ "App.s", comptime @import("native/emitter.zig").assembly(@import("native/program.zig").named(name))), "lab/native/" ++ name ++ "App.s");
        const native_plist = b.addInstallFile(native_files.add(name ++ ".plist", plistFor(name)), "Zwift" ++ name ++ ".app/Contents/Info.plist");
        const native_sign = b.addSystemCommand(&.{ "codesign", "--force", "--sign", "-", b.getInstallPath(.prefix, "Zwift" ++ name ++ ".app") });
        native_sign.step.dependOn(&native_install.step);
        native_sign.step.dependOn(&native_plist.step);
        const native_step = b.step("lab-" ++ step_name, "Build a Zig-emitted SwiftUI View and App without swiftc");
        native_step.dependOn(&native_sign.step);
        native_step.dependOn(&native_asm.step);
        native_all.dependOn(native_step);
        const native_open = b.addSystemCommand(&.{ "open", "-n", b.getInstallPath(.prefix, "Zwift" ++ name ++ ".app") });
        native_open.step.dependOn(&native_sign.step);
        b.step("run-lab-" ++ step_name, "Launch the native Swift ABI application").dependOn(&native_open.step);
        const native_smoke = b.addSystemCommand(&.{"python3"});
        native_smoke.addFileArg(b.path("lab/native/run_smoke.py"));
        native_smoke.addArg(b.getInstallPath(.prefix, "Zwift" ++ name ++ ".app/Contents/MacOS/Zwift" ++ name));
        native_smoke.step.dependOn(&native_sign.step);
        b.step("lab-" ++ step_name ++ "-test", "Check native type discovery, conformances and SwiftUI App launch").dependOn(&native_smoke.step);
        native_test_all.dependOn(&native_smoke.step);
    }
    const model_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("lab/native/tests.zig"), .target = target, .optimize = optimize }) });
    native_test_all.dependOn(&b.addRunArtifact(model_tests).step);
    const native_oracle = b.addSystemCommand(&.{"python3"});
    native_oracle.addFileArg(b.path("lab/native/check_oracle.py"));
    native_oracle.addArg(platform.swift_target);
    b.step("lab-native-oracle", "Optional development check of native ABI contracts against swiftc").dependOn(&native_oracle.step);
    const no_swift = b.addSystemCommand(&.{"python3"});
    no_swift.addFileArg(b.path("lab/native/check_no_swift.py"));
    no_swift.addArgs(&.{ b.graph.zig_exe, @tagName(optimize) });
    b.step("lab-native-no-swift-test", "Cold-build and launch with Swift compiler execution denied").dependOn(&no_swift.step);
    const generator = b.addExecutable(.{ .name = "zwift-generate", .root_module = b.createModule(.{
        .root_source_file = b.path("lab/generate.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .link_libc = true,
    }) });
    const gen = b.addRunArtifact(generator);
    const generated = gen.addOutputDirectoryArg("generated");
    const install_generated = b.addInstallDirectory(.{ .source_dir = generated, .install_dir = .prefix, .install_subdir = "lab/generated" });
    const generate_step = b.step("lab-generate", "Generate Swift entry points and ABI declarations with Zig");
    generate_step.dependOn(&install_generated.step);
    const lib = b.addLibrary(.{ .name = "zwift_lab", .linkage = .static, .root_module = b.createModule(.{
        .root_source_file = b.path("lab/library.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }) });
    const all = b.step("lab", "Build three SwiftUI apps with Zig logic and native Swift ABI probes (Apple ARM64)");
    all.dependOn(&install_generated.step);
    const oracle = b.addSystemCommand(&.{"python3"});
    oracle.addFileArg(b.path("lab/abi/check.py"));
    oracle.addDirectoryArg(generated);
    b.step("lab-abi-check", "Check native signatures against Swift compiler IR").dependOn(&oracle.step);
    inline for (.{ "Todo", "Editor", "Browser" }) |name| {
        const compile = swiftCompiler(b, lib, generated);
        compile.step.dependOn(&oracle.step);
        compile.addFileArg(b.path("lab/swift/" ++ name ++ ".swift"));
        compile.addFileArg(generated.path(b, name ++ "App.swift"));
        compile.addArg("-o");
        const exe = compile.addOutputFileArg("Zwift" ++ name);
        const install = b.addInstallFile(exe, "Zwift" ++ name ++ ".app/Contents/MacOS/Zwift" ++ name);
        const wf = b.addWriteFiles();
        const plist = wf.add(name ++ ".plist", plistFor(name));
        const install_plist = b.addInstallFile(plist, "Zwift" ++ name ++ ".app/Contents/Info.plist");
        const sign = b.addSystemCommand(&.{ "codesign", "--force", "--sign", "-", b.getInstallPath(.prefix, "Zwift" ++ name ++ ".app") });
        sign.step.dependOn(&install.step);
        sign.step.dependOn(&install_plist.step);
        const step = b.step("lab-" ++ name, "Build Zwift" ++ name ++ ".app");
        step.dependOn(&sign.step);
        all.dependOn(&sign.step);
        const open = b.addSystemCommand(&.{ "open", "-n", b.getInstallPath(.prefix, "Zwift" ++ name ++ ".app") });
        open.step.dependOn(&sign.step);
        b.step("run-lab-" ++ name, "Run Zwift" ++ name ++ ".app").dependOn(&open.step);
    }
    const tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("lab/core.zig"), .target = target, .optimize = optimize, .link_libc = true }) });
    const run_tests = b.addRunArtifact(tests);
    const smoke = swiftCompiler(b, lib, generated);
    smoke.step.dependOn(&oracle.step);
    const smoke_files = b.addWriteFiles();
    const smoke_plist = smoke_files.add("Smoke.plist", plistFor("Smoke"));
    smoke.addArgs(&.{ "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker" });
    smoke.addFileArg(smoke_plist);
    inline for (.{ "Todo", "Editor", "Browser", "Smoke" }) |name| smoke.addFileArg(b.path("lab/swift/" ++ name ++ ".swift"));
    smoke.addArg("-o");
    const smoke_exe = smoke.addOutputFileArg("lab-smoke");
    const run_smoke = b.addSystemCommand(&.{"python3"});
    run_smoke.addFileArg(b.path("lab/run_smoke.py"));
    run_smoke.addFileArg(smoke_exe);
    run_smoke.addArg(b.getInstallPath(.prefix, "lab/screenshots"));
    const test_step = b.step("lab-test", "Run Zig state tests, Swift ABI/Observation tests and WebKit smoke tests");
    test_step.dependOn(&run_tests.step);
    const view_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("lab/views/tests.zig"), .target = target, .optimize = optimize }) });
    test_step.dependOn(&b.addRunArtifact(view_tests).step);
    test_step.dependOn(&run_smoke.step);
    all.dependOn(&oracle.step);
    test_step.dependOn(&oracle.step);
    const bench_lib = b.addLibrary(.{ .name = "zwift_bench", .linkage = .static, .root_module = b.createModule(.{
        .root_source_file = b.path("lab/library.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
    }) });
    const bench = swiftCompiler(b, bench_lib, generated);
    bench.step.dependOn(&oracle.step);
    bench.addFileArg(generated.path(b, "ABIReferences.swift"));
    inline for (.{ "Todo", "Editor", "Bench" }) |name| bench.addFileArg(b.path("lab/swift/" ++ name ++ ".swift"));
    bench.addArg("-o");
    const bench_exe = bench.addOutputFileArg("lab-bench");
    const run_bench = b.addSystemCommand(&.{"python3"});
    run_bench.addFileArg(b.path("lab/run_bench.py"));
    run_bench.addFileArg(bench_exe);
    run_bench.addArg(b.getInstallPath(.prefix, "lab/performance.json"));
    b.step("lab-bench", "Measure native ABI, generated views, callbacks and editor copies (optimized)").dependOn(&run_bench.step);
    const launch = b.addSystemCommand(&.{"python3"});
    launch.addFileArg(b.path("lab/launch_smoke.py"));
    launch.addArg(b.getInstallPath(.prefix, ""));
    launch.step.dependOn(all);
    b.step("lab-launch-test", "Launch and capture each real Swift App entry point").dependOn(&launch.step);
}
fn swiftCompiler(b: *std.Build, lib: *std.Build.Step.Compile, generated: std.Build.LazyPath) *std.Build.Step.Run {
    const cmd = b.addSystemCommand(&.{ "swiftc", "-swift-version", "6", "-warnings-as-errors", "-O", "-g", "-parse-as-library", "-target", platform.swift_target, "-framework", "SwiftUI", "-framework", "WebKit", "-framework", "AppKit", "-import-objc-header" });
    cmd.addFileArg(generated.path(b, "Bridge.h"));
    cmd.addFileArg(generated.path(b, "NativeABI.swift"));
    cmd.addFileArg(generated.path(b, "GeneratedViews.swift"));
    cmd.addFileArg(b.path("lab/swift/Shared.swift"));
    cmd.addArtifactArg(lib);
    return cmd;
}
fn plistFor(comptime name: []const u8) []const u8 {
    return
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    \\<plist version="1.0"><dict>
    ++ "<key>CFBundleExecutable</key><string>Zwift" ++ name ++ "</string>" ++
        "<key>CFBundleIdentifier</key><string>dev.zwift.lab." ++ name ++ "</string>" ++
        "<key>CFBundleName</key><string>Zwift " ++ name ++ "</string>" ++
        "<key>CFBundleVersion</key><string>1</string><key>CFBundlePackageType</key><string>APPL</string>" ++
        "<key>LSMinimumSystemVersion</key><string>" ++ platform.minimum_string ++ "</string>" ++
        "<key>NSHighResolutionCapable</key><true/>" ++
        "<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>" ++
        "</dict></plist>";
}

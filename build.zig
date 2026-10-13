const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    if (comptime @import("builtin").os.tag == .macos) @import("lab/build.zig").add(b, optimize);

    // ── Shared zwift module ────────────────────────────────────────────

    const zwift = b.createModule(.{
        .root_source_file = b.path("src/zwift.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    zwift.linkFramework("AppKit", .{});
    zwift.linkFramework("WebKit", .{});
    zwift.linkFramework("CoreGraphics", .{});
    zwift.linkFramework("Accessibility", .{});
    zwift.linkFramework("ApplicationServices", .{});
    zwift.linkSystemLibrary("objc", .{});

    // ── Todoz app ─────────────────────────────────────────────────────

    const exe = b.addExecutable(.{
        .name = "todoz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/app.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    exe.root_module.linkFramework("AppKit", .{});
    exe.root_module.linkFramework("CoreGraphics", .{});
    exe.root_module.linkFramework("Accessibility", .{});
    exe.root_module.linkFramework("ApplicationServices", .{});
    exe.root_module.linkSystemLibrary("objc", .{});

    // ── App bundle (Zig) ───────────────────────────────────────────────

    const zig_step = b.step("app-zig", "Build TodozZig.app bundle (Zig + AppKit)");
    const bundle = makeAppBundle(b, "TodozZig", "org.nounder.todoz");

    const install_exe = b.addInstallArtifact(exe, .{});
    const cp_exe = b.addSystemCommand(&.{
        "cp",
        b.getInstallPath(.bin, "todoz"),
        b.getInstallPath(.prefix, "TodozZig.app/Contents/MacOS/TodozZig"),
    });
    cp_exe.step.dependOn(&install_exe.step);
    cp_exe.step.dependOn(bundle);
    zig_step.dependOn(&cp_exe.step);

    // ── App bundle (Swift) ─────────────────────────────────────────────

    const swift_step = b.step("app-swift", "Build TodozSwift.app bundle (SwiftUI)");
    const swift_bundle = makeAppBundle(b, "TodozSwift", "org.nounder.todoz.swift");

    const swift_exe_path = b.getInstallPath(.prefix, "TodozSwift.app/Contents/MacOS/TodozSwift");

    const swiftc = b.addSystemCommand(&.{
        "swiftc",
        "-O",
        "-parse-as-library",
        "-framework",
        "SwiftUI",
        "-framework",
        "AppKit",
        "-framework",
        "CoreGraphics",
        "-o",
    });
    swiftc.addArg(swift_exe_path);
    swiftc.addFileArg(b.path("swift/App.swift"));
    swiftc.step.dependOn(swift_bundle);
    swift_step.dependOn(&swiftc.step);

    // ── Run ────────────────────────────────────────────────────────────

    const run_zig_step = b.step("run-zig", "Build and open TodozZig.app");
    const open_app = b.addSystemCommand(&.{ "open", b.getInstallPath(.prefix, "TodozZig.app") });
    open_app.step.dependOn(&cp_exe.step);
    run_zig_step.dependOn(&open_app.step);

    const run_swift_step = b.step("run-swift", "Build and open TodozSwift.app");
    const open_swift = b.addSystemCommand(&.{ "open", b.getInstallPath(.prefix, "TodozSwift.app") });
    open_swift.step.dependOn(&swiftc.step);
    run_swift_step.dependOn(&open_swift.step);

    // ── Examples ───────────────────────────────────────────────────────

    addExample(b, zwift, target, optimize, "floating_webview_zig");
    addExample(b, zwift, target, optimize, "html_textview");
    if (comptime @import("builtin").os.tag == .macos) {
        addSwiftUIExample(b, target, optimize, "floating_webview_swiftui", &.{});
        addSwiftUIExample(b, target, optimize, "todoz_swiftui", &.{"examples/todoz_swiftui/bridge.swift"});
    }

    // ── Default: build both apps ──────────────────────────────────────

    b.getInstallStep().dependOn(&cp_exe.step);
    b.getInstallStep().dependOn(&swiftc.step);

    // ── Tests ──────────────────────────────────────────────────────────

    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/app.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);
}

// ── Example helper ─────────────────────────────────────────────────────

fn addExample(
    b: *std.Build,
    zwift: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
) void {
    const example = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/" ++ name ++ "/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{.{ .name = "zwift", .module = zwift }},
        }),
    });
    example.root_module.linkFramework("AppKit", .{});
    example.root_module.linkFramework("WebKit", .{});
    example.root_module.linkFramework("CoreGraphics", .{});
    example.root_module.linkFramework("Accessibility", .{});
    example.root_module.linkFramework("ApplicationServices", .{});
    example.root_module.linkSystemLibrary("objc", .{});

    const run = b.addRunArtifact(example);
    b.step("check-" ++ name, "Compile " ++ name ++ " without launching it").dependOn(&example.step);
    const step = b.step("run-" ++ name, "Run " ++ name ++ " example");
    step.dependOn(&run.step);
}

// ── Swift toolchain resolution ─────────────────────────────────────────

const SwiftPaths = struct { toolchain_swift_lib: []const u8, sdk_swift_lib: []const u8 };

fn resolveSwiftPaths(b: *std.Build) SwiftPaths {
    const S = struct {
        var cached: ?SwiftPaths = null;
    };
    if (S.cached) |paths| return paths;

    const clang = std.mem.trim(u8, b.run(&.{ "xcrun", "--find", "clang" }), &std.ascii.whitespace);
    // Resolve runtime libraries without requiring the Swift compiler executable.
    const toolchain_root = std.fs.path.dirname(std.fs.path.dirname(clang).?).?;

    const sdk = std.mem.trim(u8, b.run(&.{ "xcrun", "--show-sdk-path" }), &std.ascii.whitespace);

    S.cached = .{
        .toolchain_swift_lib = b.fmt("{s}/lib/swift/macosx", .{toolchain_root}),
        .sdk_swift_lib = b.fmt("{s}/usr/lib/swift", .{sdk}),
    };
    return S.cached.?;
}

// ── SwiftUI example helper ─────────────────────────────────────────────
//
// Builds a Zig executable that links the Swift runtime + SwiftUI framework.
// If a matching .swift file exists, it is compiled to .o and linked in.

fn addSwiftUIExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
    comptime swift_files: []const []const u8,
) void {
    const swift_paths = resolveSwiftPaths(b);

    const example = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/" ++ name ++ "/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    // Compile companion Swift files
    inline for (swift_files) |swift_path| {
        const swiftc_cmd = b.addSystemCommand(&.{ "swiftc", "-parse-as-library", "-emit-object", "-o" });
        const swift_obj = swiftc_cmd.addOutputFileArg(swift_path ++ ".o");
        swiftc_cmd.addFileArg(b.path(swift_path));
        example.root_module.addObjectFile(swift_obj);
    }

    // Swift runtime library paths
    example.root_module.addLibraryPath(.{ .cwd_relative = swift_paths.toolchain_swift_lib });
    example.root_module.addLibraryPath(.{ .cwd_relative = swift_paths.sdk_swift_lib });
    example.root_module.addRPath(.{ .cwd_relative = "/usr/lib/swift" });

    // Swift core + overlay libraries
    const swift_libs = [_][]const u8{
        "swiftCore",           "swiftCoreFoundation",         "swiftCoreImage",
        "swiftDispatch",       "swiftIOKit",                  "swiftMetal",
        "swiftOSLog",          "swiftObjectiveC",             "swiftQuartzCore",
        "swiftSpatial",        "swiftUniformTypeIdentifiers", "swiftXPC",
        "swift_Builtin_float", "swiftos",                     "swiftsimd",
        "swiftObservation",    "swift_Concurrency",
    };
    for (swift_libs) |lib| {
        example.root_module.linkSystemLibrary(lib, .{});
    }

    // Frameworks
    example.root_module.linkFramework("SwiftUI", .{});
    example.root_module.linkFramework("AppKit", .{});
    example.root_module.linkFramework("Foundation", .{});
    example.root_module.linkSystemLibrary("objc", .{});

    const run = b.addRunArtifact(example);
    b.step("check-" ++ name, "Compile " ++ name ++ " without launching it").dependOn(&example.step);
    const step = b.step("run-" ++ name, "Run " ++ name ++ " example");
    step.dependOn(&run.step);
}

// ── App bundle helper ──────────────────────────────────────────────────

const plist_template =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    \\<plist version="1.0">
    \\<dict>
    \\  <key>CFBundleName</key>
    \\  <string>{[name]s}</string>
    \\  <key>CFBundleIdentifier</key>
    \\  <string>{[id]s}</string>
    \\  <key>CFBundleVersion</key>
    \\  <string>1.0</string>
    \\  <key>CFBundleShortVersionString</key>
    \\  <string>1.0</string>
    \\  <key>CFBundlePackageType</key>
    \\  <string>APPL</string>
    \\  <key>CFBundleExecutable</key>
    \\  <string>{[name]s}</string>
    \\  <key>LSMinimumSystemVersion</key>
    \\  <string>13.0</string>
    \\  <key>NSHighResolutionCapable</key>
    \\  <true/>
    \\</dict>
    \\</plist>
    \\
;

/// Creates the .app/Contents/{MacOS,Resources,Info.plist} skeleton.
/// Returns a step that, once complete, guarantees the dirs and plist exist.
/// The caller is responsible for getting the executable into Contents/MacOS/.
fn makeAppBundle(b: *std.Build, app_name: []const u8, bundle_id: []const u8) *std.Build.Step {
    const contents = b.fmt("{s}.app/Contents", .{app_name});

    const mkdir = b.addSystemCommand(&.{
        "mkdir",                                                    "-p",
        b.getInstallPath(.prefix, b.fmt("{s}/MacOS", .{contents})), b.getInstallPath(.prefix, b.fmt("{s}/Resources", .{contents})),
    });

    const plist_content = b.fmt(plist_template, .{ .name = app_name, .id = bundle_id });
    const wf = b.addWriteFiles();
    const plist_file = wf.add("Info.plist", plist_content);
    const install_plist = b.addInstallFile(plist_file, b.fmt("{s}/Info.plist", .{contents}));
    install_plist.step.dependOn(&mkdir.step);

    return &install_plist.step;
}

# Zig → Swift ABI / SwiftUI experiments

Three **applications build without swiftc**: Native (Text), Animations
(TimelineView/Canvas), and Paint (NSViewRepresentable). Zig emits their nominal
types, conformances, bodies and SwiftUI `App` entry points. Apple supplies the
existing Swift runtime and UI frameworks.

The earlier three application harnesses retain two paths: Zig emits ten audited ARM64 Swift ABI
specializations, and a typed Zig AST emits concrete SwiftUI view structs.
All three apps use generated controls. The generated state panel initializes
real `@State` and `@Environment` backing properties through Zig's ABI factories.

Swift compiles those generated views and provides their protocol conformances,
property-wrapper installation, key paths, generic metadata and App lifecycle.
Platform adapters and the outer app layouts are still handwritten Swift. This
is not a general Swift ABI backend or an entirely Zig-authored UI. Python handles
verification, fixtures and benchmark reporting; there is no C/C++ implementation.

## Native View and App emission: first complete executable

`native/program.zig` is a typed, bounded input to `native/emitter.zig`. The
emitter runs during Zig compilation and produces ARM64 instructions and Mach-O
data/relocations through module assembly. There is no checked-in Swift object,
no compilation of generated Swift, and no AppKit-created replacement window.
The Zig process entrypoint calls SwiftUI's real `App.main`, passing the emitted
application metadata in both the generic argument and Swift self register, plus
the App witness table. SwiftUI owns the application lifecycle and window creation.

What is emitted:

- Module and nominal struct descriptors, metadata accessors and field records.
- Empty struct metadata using the runtime's shared empty-tuple value witnesses.
- Resilient `View` and `App` conformance records: six and four requirements,
  respectively. `swift_getWitnessTable` assembles their tables using current
  protocol requirement descriptors; the backend does not guess fixed table slots.
- Mangled associated body type references for `Text` and `WindowGroup<ZigRoot>`,
  with associated conformance accessors.
- `View` default implementation thunks, an indirect `Text` body getter, an
  indirect `WindowGroup` body getter, and a capture-free root initializer closure.
- Calls to framework generic metadata accessors, the `WindowGroup` initializer,
  the String/Text initializers, and `App.main`, with the required register/stack
  argument placement and unwind information.
- Swift type/conformance discovery sections, an entry record and the Swift ABI
  image marker used by the loader.

The distinction between value witnesses (copy/destroy/layout) and protocol
witnesses (conformance requirements) matters. An empty struct can reuse the
former from the Swift runtime. Adding `State` fields will require different
value operations and field layout metadata, as well as testing SwiftUI property
discovery and installation. See Swift's [metadata documentation](https://github.com/swiftlang/swift/blob/main/docs/ABI/TypeMetadata.rst)
and [current ABI flag definitions](https://github.com/swiftlang/swift/blob/main/include/swift/ABI/MetadataValues.h).

Two integration failures were found and fixed:

1. Without `__objc_imageinfo` carrying the stable Swift ABI version, directly
   addressed metadata had a name, but runtime nominal lookup did not find our
   type. Emitting the image marker made type and conformance discovery work.
2. A normal global label at the metadata address point let the optimized linker
   separate its preceding value-witness pointer. Debug launched; ReleaseFast
   crashed while SwiftUI read layout information. An alternate entry at offset
   eight keeps the prefix and record in one linker atom. Both runtime modes now
   check this prefix before entering SwiftUI.

Verification is split deliberately:

```sh
./scripts/zig build lab-native-test
./scripts/zig build lab-native-test -Doptimize=ReleaseFast
./scripts/zig build lab-native-no-swift-test
./scripts/zig build lab-native-no-swift-test -Doptimize=ReleaseFast
./scripts/zig build lab-native-oracle
```

The launch probe checks qualified runtime type names, nominal lookup, positive
and negative protocol conformance lookup, generic metadata completion and Scene
conformance, and value-witness prefix placement. It then checks that SwiftUI
evaluates both bodies on the main thread and creates a visible window with a
nonempty content frame. It observes the window through Objective-C and terminates
normally; it does not install a host view or create the window itself.
It also launches a second process without metadata preflight, so SwiftUI is
tested with initially cold generic metadata and witness caches.

The cold-build check uses fresh local/global Zig caches and a fresh install
prefix under `sandbox-exec`, denying `swift`, `swiftc`, and `swift-frontend`
execution. It first verifies its deny rule with a harmless test executable,
audits the application compile command for Swift/precompiled object inputs,
and launches all three native examples under the same restriction. Logs are kept in
`zig-out/lab/native/no-swift-{Debug,ReleaseFast}.log`.

The optional oracle compiles `native/oracle.swift` and `native/oracle/*.swift`
only to temporary LLVM IR.
It checks call signatures, indirect body results, resilient conformance records,
and empty struct metadata against the installed compiler. It is never linked
into the native app and is not part of its build graph. These checks do not
constitute a proof of compatibility with every future SDK/runtime.

Scope and next steps:

- This is a backend for three concrete type graphs, not a general Swift compiler.
  Type names and UTF-8 literal text are supplied by Zig; the literal currently
  has a 65,535-byte limit. Apple ARM64 only, deployment target macOS 26. Runtime
  execution on macOS 26 remains untested; execution here was on 27.0.1.
- The seven-component typed Swift-source DSL remains the reference path; its
  arbitrary view trees are not yet accepted by the native backend. Unsupported
  constructs do not silently invoke swiftc.
- Next: a nonempty view with installed `State<UInt64>` and an owned button
  closure. Test mutation and persistence across parent reconstruction before
  adding bindings, environment key paths or more layout types.
- After that, add per-item Zig events/subscription tokens and row-local state
  invalidation. A generated equivalent of `@Observable` is a later option,
  not a prerequisite for the first granular update experiment.
- The existing todo, editor and browser harnesses still use swiftc. Their
  snapshots, single observer limitation and platform adapters are unchanged.

## Animations and Paint without swiftc

```sh
./scripts/zig build run-lab-Animations
./scripts/zig build run-lab-Paint
./scripts/zig build lab-native-examples-test
./scripts/zig build lab-native-examples-test -Doptimize=ReleaseFast
./scripts/zig build lab-native-no-swift-test
./scripts/zig build lab-native-no-swift-test -Doptimize=ReleaseFast
```

The native programs share the View/App emitter. They select a body specialization
at comptime; they do not introduce a Swift source-generation build dependency.
Both Debug and ReleaseFast are tested on this macOS 27.0.1 ARM64 host. macOS 26
runtime coverage remains outstanding.
The final combined optimized regression run passed 57/57 build steps and 17/17
Zig tests, plus the native runtime checks, ABI oracles, existing mounted SwiftUI
and WebKit checks, and all three older app launches. Fresh-cache compiler-denied
builds and both launch modes passed for all native examples in Debug and
ReleaseFast.

**Animations** returns the concrete SwiftUI type
`TimelineView<AnimationTimelineSchedule, Canvas<EmptyView>>`. SwiftUI calls an
emitted content closure on its animation schedule; that closure constructs a
Canvas whose renderer captures a timestamp. The renderer calls
`GraphicsContext.withCGContext`, then a Zig drawing callback. Translation,
rotation, scale and opacity come from a deterministic, four-second Zig animation
function. The schedule requests a 1/60-second minimum interval; this is not a
measured or guaranteed frame rate. The clock is `CACurrentMediaTime`, sampled
when SwiftUI requests content, rather than `TimelineView.Context.date`.

This exercises two closure lifetimes: an escaping Swift heap context containing
the timestamp and a borrowed stack context for `withCGContext`. Zig emits the
heap metadata and Swift-self destructor thunk; Swift retains/releases the
context when Canvas values are copied or destroyed. The throwing closure ABI's
error register is preserved even though our drawing callback cannot throw.
The runtime test copies a real Canvas through its value witnesses, destroys the
original, verifies the capture remains alive, then destroys the copy and checks
exactly one destruction. Live checks also require changing rendered frames and
release of superseded captures.

Resilient SDK value sizes are read from runtime metadata. Schedule and color-mode
buffers are consumed by Swift initializers, so Zig frees their storage without
destroying a second time. `runtime.zig` centralizes allocation, copying and
destruction; it explicitly rejects alignment beyond malloc's guarantee.
The optional Swift oracle deliberately checks the exported TimelineView
initializer underlying the SDK's newer context convenience overload.

These are **timeline-driven Canvas animations**, not implicit SwiftUI
`withAnimation`, `.animation(_:value:)`, spring transitions or installed native
`@State`. Supporting those remains a separate ABI specialization project.

**Paint** uses an empty root conforming to both View and NSViewRepresentable.
Zig emits all 14 resilient representable requirements, including inherited View
conformance, `NSViewType = NSView`, `Coordinator = Void`, lifecycle callbacks,
layout defaults and size negotiation. `View.Body = Never`: SwiftUI uses the
representable's primitive make-view implementations; it must not evaluate a
body getter. The root callback counted by the probe is `makeNSView` in this app.

The NSView subclass and its Objective-C methods are implemented in Zig. Each
view owns an independent allocator-backed stroke model. Brush settings are
captured when a stroke starts, completed strokes retain their point buffers,
and undo/redo moves a visible-history cursor. A new stroke after undo discards
the redo branch only after reserving enough storage. The eraser paints white
onto the white canvas. Clear discards history; there is no file persistence.

Tests cover deterministic animation math; stroke ownership and brush snapshots;
undo/redo branching; independent models; invalid points; and every allocation
failure in a stroke scenario. Mounted Paint tests send NSEvents through
NSWindow for palette, width, drawing, erasing, undo/redo (buttons and keyboard)
and clear. They check CoreGraphics pixels, actual NSView drawing callbacks, and
SwiftUI's make/update/dismantle/dealloc sequence. Closing the SwiftUI-created
window and detaching its content releases the model. Merely detaching content
was insufficient because the window's SwiftUI owner retained the hosting tree.
AppKit's `acceptsFirstMouse` is needed to deliver the first click to the canvas
when the test application's window is inactive. Finished strokes keep one
CGPath each. Later redraws stroke that path instead of walking every point.
The stroke under the pointer is still rebuilt until mouse-up. Undo and redo
move the visibility cursor and do not copy points or paths.

Observed runs have one App body evaluation and one initial root callback for
each app. Animation frames and Paint strokes do not reconstruct the outer
SwiftUI root or copy a Swift snapshot of the drawing. Paint redraws its NSView
directly. This demonstrates a local invalidation path for a platform view; it
does **not** fix the older Todo store's broad invalidation or single observer.

Remaining costs and small next improvements:

- Animation currently allocates a temporary color-mode buffer and one Swift
  capture per Canvas construction. The capture matches Swift's normal escaping
  closure ownership. Reusing bounded temporary storage would remove the extra
  allocation; no frame-time performance advantage is claimed here.
- Finished strokes are retained CGPaths, so a redraw no longer walks their
  points. Cost still grows with the number of strokes, because each path is
  replayed. A backing bitmap is the next step for long drawings. Undo/redo
  does not copy point arrays or paths.
- Move the animation callback's time input to the timeline context when cadence
  and timeline-controlled pause semantics are needed. Add that getter as another
  independently checked specialization.
- Continue with nonempty root metadata and DynamicProperty installation for
  true `@State`-driven animation, then add transaction/Animation calls. Captured
  renderer closures working here supply ownership machinery, not property-wrapper
  discovery or implicit interpolation automatically.

`ZWIFT_NATIVE_CAPTURE=/absolute/path.png` with `ZWIFT_NATIVE_PROBE=metadata`
saves a diagnostic PNG of the hosted view before test teardown. Captures from
this run are in `zig-out/lab/native/screenshots/`. The regular launch has no test
input injection or automatic termination.

## Run and inspect

From the repository root:

```sh
./scripts/zig build lab
./scripts/zig build lab-test lab-launch-test
./scripts/zig build lab-bench
open zig-out/ZwiftTodo.app
open zig-out/ZwiftEditor.app
open zig-out/ZwiftBrowser.app
```

Build commands `lab-Todo`, `lab-Editor`, `lab-Browser` select one app.
`lab-generate` installs `Bridge.h`, `NativeABI.swift`, `GeneratedViews.swift`,
`ABIReferences.swift`, `ABIManifest.json`, `NativeABI.s`, and three real Swift
`@main App` sources into `zig-out/lab/generated/`. Assembly is emitted directly
inside Zig; the `.s` copy is for inspection.
The existing `zig build` default continues to build the original two apps.

Source map:

| File | Responsibility |
| --- | --- |
| `platform.zig` | Shared minimum macOS version for Zig, Swift, ABI oracle and app bundles |
| `native/program.zig`, `native/emitter.zig` | Native application definition and bounded Swift ABI type/conformance backend |
| `native/probe.zig`, `native/run_smoke.py` | Runtime metadata checks and actual SwiftUI application launch verification |
| `native/check_no_swift.py`, `native/check_oracle.py` | Guarded cold builds and separate optional compiler oracle |
| `native/animation_abi.zig`, `native/animation.zig`, `native/motion.zig` | TimelineView/Canvas ABI adapters, renderer ownership and deterministic animation |
| `native/surface_abi.zig`, `native/paint.zig`, `native/paint_model.zig` | NSViewRepresentable conformance, Zig NSView adapter and owned stroke history |
| `native/runtime.zig`, `native/cg.zig`, `native/tests.zig` | Swift value-witness operations, CoreGraphics boundary and model tests |
| `core.zig` | Per-instance owned data, todo operations, UTF-8 text/stats, URL normalization, environment snapshot, callbacks |
| `generate.zig` | Comptime reflection into C declarations; generation of native Swift declarations and App entry points |
| `abi/schema.zig`, `abi/native.zig` | Audited specialization registry, ARM64 lowering, declarations and Zig helpers |
| `abi/check.py` | Independently compiled Swift reference functions checked against the ABI manifest |
| `views/schema.zig`, `views/dsl.zig`, `views/apps.zig` | Typed AST, contextual diagnostics, convenience helpers, Swift emitter and seven components |
| `views/tests.zig` | Rejection of invalid programs, escaping and component wiring tests |
| `swift/Shared.swift` | Swift ownership boundary, settings and app shell |
| `swift/Todo.swift` | Callback → `@Observable` → `@Environment` model |
| `swift/Editor.swift` | Immutable snapshots → `@State` → text `Binding`, `FileDocument` |
| `swift/Browser.swift` | Custom `DynamicProperty`, installed `@State`, `Binding`, WebKit representable/delegate |
| `swift/Smoke.swift` | Mounted view identity tests, ABI tests, ownership stress and WebKit integration |
| `swift/Bench.swift`, `run_bench.py` | ABI, typed-view, model and editor benchmarks |

## State ownership approaches

| Approach | Data owner and invalidation | Benefit | Cost / boundary |
| --- | --- | --- | --- |
| Todo: callback + Observation | Zig owns todos; synchronous change callback replaces a Swift `@Observable` snapshot | Natural environment injection; Zig-originated mutations invalidate readers | Current invalidation replaces the entire array; one observer per store |
| Editor: value reducer + State | Zig accepts an edit and computes stats; Swift assigns the result to `@State` | Simple unidirectional flow; easy testing; standard TextEditor binding | Copies the whole document into Zig and rescans it on every edit |
| Browser: DynamicProperty | Zig owns normalized submitted address; nested `@State` owns handle identity and revision | Reusable SwiftUI property-wrapper syntax; projected `Binding` | Out-of-band Zig writes need callbacks/stream integration to bump revision |
| Native factories | Zig constructs actual SwiftUI wrappers; Swift view stores them as backing properties | Real Swift ABI and installed `@State`/`@Environment`, not lookalike wrappers | Concrete ARM64 specializations; Swift compiler still supplies view metadata/conformance |
| Typed view generation | Named Zig fields become real Swift `@State`/`@Binding`/`@Environment` fields | Concrete result-builder types and SwiftUI identity; no runtime tree interpreter | Closed DSL; platform operations still use Swift adapters |

The browser intentionally separates its editable address draft, its last
Zig-normalized submission, and WebKit's current URL/history. Typing must not
navigate on every keystroke. Link clicks and history changes update the displayed
address from WebKit; WebKit remains the owner of actual page/history state.

The todo model is placed in the environment with `.environment(model)` and
consumed via `@Environment(TodoModel.self)`. Each window owns a separate store;
there is no global model. Drag payloads contain both a stable item ID and a
window session UUID, so dropping a row from another window cannot accidentally
reorder an unrelated item with the same numeric ID. A row is moved before another
ID (or to the end), which also works when the list is filtered.

## What the native ABI code actually does

`@_silgen_name` changes symbol naming while retaining the **Swift calling
convention**. It does not make a function C-callable. The normal data API uses
Zig C exports imported through a generated header. Only the explicit native
experiment uses `@_silgen_name` declarations.

On the tested Apple ARM64 toolchain:

| Signature | Lowering observed from swiftc |
| --- | --- |
| `UInt64 -> NativeQuad` | Four result words in `x0…x3`; C would return a 32-byte struct indirectly |
| `UInt64 -> Text` | Result words in `x0`, `x1`, `w2`, `x3` |
| `UInt64 -> State<UInt64>` | Two result words in `x0`, `x1` |
| `Bool -> State<Bool>` | Bool in `w0`, reference word in `x1` |
| `Double -> State<Double>` | Mixed register classes: `d0` and **`x0`**, not `x1` |
| `String -> State<String>` | Borrowed input in `x0/x1`; owned result in `x0/x1/x2` |
| `KeyPath<EnvironmentValues, Bool/Double> -> Environment<Bool/Double>` | Two specializations; payload in `x0`, tag in `w1` |
| `Bool -> Binding<Bool>` | Constant binding in `x0/x1/w2`; writes are intentionally ignored |
| `String -> Text` | Borrowed String retained before the consuming initializer; result in `x0/x1/w2/x3` |

The quad adapter calls a Zig C helper that fills a stack buffer, then loads the
Swift result registers. This makes the calling-convention difference observable
without depending on framework behavior.

The Text adapter gets an immortal ASCII literal from Zig, calls Swift's string
literal initializer, then calls `Text.init(verbatim:)`. The Swift result owns
the resulting value. Literals are static because that initializer can use
immortal storage; passing temporary Zig buffers through this path would be wrong.

The UInt64 State adapter passes a pointer to the seed and the exported `UInt64` metadata
to the generic initializer. Its indirect result buffer is passed in `x8`; the
specialized wrapper is returned in `x0/x1`. The Environment adapter accepts a
Swift-generated key path, retains that borrowed argument for the consuming
initializer, supplies an `x8` result buffer, and returns the payload/tag. Zig
does not generate the key-path object or the generic type metadata itself.

All adapters use aligned stack frames, emit CFI unwind directives, and preserve
the frame pointer/link register. They avoid the original experiment's unsafe pattern of keeping an
output pointer in caller-saved `x9` across a `bl` instruction without declaring
the call's register clobbers. These adapters are synchronous, nonthrowing probes;
they are not a solution for Swift async/throws/witness-method conventions.

Generated fields use the same backing-property initialization as this example:

```swift
@State private var count: UInt64
@Environment private var enabled: Bool

init() {
    _count = nativeState(0)
    _enabled = nativeEnvironment(\.isEnabled)
}
```

The test mounts a view with a Zig-created seed of 7, mutates it to 8, rebuilds
the view with a seed of 99 and verifies it stays 8, then changes `.id(...)` and
verifies it becomes 99. Environment changes from true to false and back are
observed in the mounted child. **Construction and installation are distinct**:
a Zig struct with fields named like State is not enough. SwiftUI needs its real
dynamic-property machinery and a view identity. Apple's [model-data guidance](https://developer.apple.com/documentation/SwiftUI/Managing-model-data-in-your-app)
describes this managed-storage relationship.

The compiler check verifies all ten registered signatures plus four called
framework initializer signatures. Runtime tests assert the concrete layouts.
The manifest is an explicit audited specification, not an automatic ABI
classifier; swiftc independently lowers its reference implementations. Run it on every SDK/compiler change. Swift ABI stability
does not provide a general C-style foreign-function interface to every generic
API; type metadata, ownership, value witnesses and protocol witnesses still
matter. See Swift's [ABI manifesto](https://github.com/swiftlang/swift/blob/main/docs/ABIStabilityManifesto.md)
and [type metadata specification](https://github.com/swiftlang/swift/blob/main/docs/ABI/TypeMetadata.rst).

## Environment and explicit control flow

Normal settings are a Swift `@Observable` object injected into the environment.
Each view observes color scheme and settings, then passes a small by-value
`ZWEnvironment` to Zig. Compact layout and appearance are displayed in SwiftUI;
the `allow_http` flag changes Zig's URL-validation behavior. The WebKit delegate
also applies the policy to clicked links/history navigation.

This makes the ambient dependency explicit at the language boundary. It does
not poll, access private environment storage, or pretend Zig has Swift property
wrappers. The typed DSL uses named fields and SwiftUI structural identity, with stable
`Identifiable` keys in generated `ForEach`. It does not index state slots by
call order. A Zig-owned runtime renderer would need to recreate this identity
contract explicitly.

Zig's explicit control flow is therefore manageable. The harder parts are view
identity, invalidation, ownership, and Swift protocol/generic metadata. A Zig
`if` can select a typed UI node; the runtime still needs to know whether that
selection preserves or replaces a component's identity.

## Typed Zig view generation

`views/apps.zig` uses small functions from `views/dsl.zig` to build the existing
typed AST. Helpers cover fields, scalar literals, stacks, controls, modifiers,
actions, branches and keyed components. They add no runtime layer. For example:

```zig
const ui = @import("dsl.zig");
const counter: ui.View = .{
    .name = "Counter",
    .fields = &.{ui.state("count", ui.uint(0), .native)},
    .body = ui.vstack(8, &.{
        ui.text(ui.describe(ui.ref(.uint, "count"))),
        ui.button(ui.str("Increment"), ui.increment(ui.bind(.uint, "count"))),
    }),
};
```

With `.native`, the generated constructor assigns `_count = nativeState(0)`;
with `.swift`, it emits `State(wrappedValue: 0)`. Both use the same SwiftUI
storage installation. The same choice exists for supported environment fields.
Migrating all seven definitions produced identical Swift apart from added
view/field context comments.
Zig chooses the authored component graph at compile time. Runtime conditions
become Swift result-builder `if` branches; runtime collections become `ForEach`.
There is no `AnyView` erasure, JSON tree, dispatch interpreter or polling loop.

Validation checks actual field types even if an expression falsely claims a
matching type, binding mutability, environment-key type, action signatures,
constructor inputs, duplicate/missing component arguments, identifiers, finite
slider ranges, UTF-8 and recursive component cycles. Arguments are emitted in
the callee's declaration order. String escaping prevents accidental Swift source
interpolation. State initializers may reference inputs, not uninstalled storage.
Swift then checks its actual SDK overloads and result-builder constraints.

Validation carries one diagnostic record alongside its existing checks. Errors
name the view/field, expected type and actual type or mutability where applicable:

```text
GeneratedTodoControls.isDone: expected writable Bool; field is read-only
Counter.count: expected writable Bool; found UInt64
Parent.Child.title: missing component argument
```

Generated declarations include `// Zig view:` and `// Zig field:` comments so
Swift compiler errors can be traced back to the authored component. Negative
program tests cover these diagnostics, including errors inside nested components.


The todo checkbox row, editor statistics/font-size controls, browser toolbar,
and shared state panel are generated. App entry points remain generated too.
Two test components exercise keyed row state and one provides the benchmark
card. Mounted tests increment row state, reorder rows, remove/reinsert a row,
and remove/reinsert the enclosing conditional branch. State follows identity
and resets when that identity leaves the tree.

The DSL is deliberately closed: it currently has fixed scalar types, two
supported environment keys, one item shape, limited actions and one lexical
`ForEach` level. It does not represent arbitrary Swift expressions, modifiers,
protocol constraints or generic user models. Expanding it should add typed
nodes and validation together rather than an unchecked raw-source escape hatch.

## Measured performance and the implemented improvement

Run `./scripts/zig build lab-bench`. It always builds the Zig benchmark library
with `ReleaseFast`, compiles Swift with `-O`, and writes all seven sample values
per case to `zig-out/lab/performance.json`. A retained reference run is in
[`results/apple-m1-max.json`](results/apple-m1-max.json). These are local Apple
M1 Max measurements, not claims about other machines or an app's frame rate.

| Work per operation | Zig/native/generated | Swift reference or previous path |
| --- | ---: | ---: |
| `State<UInt64>` construction/destruction | 54.2 ns | 50.8 ns |
| `State<Bool>` | 50.6 ns | 50.6 ns |
| `State<Double>` | 50.4 ns | 50.5 ns |
| `State<String>` with a heap string | 72.5 ns | 72.5 ns |
| `Environment<Bool>` | 62.0 ns | 13.5 ns |
| `Environment<Double>` | 58.6 ns | 13.5 ns |
| Constant `Binding<Bool>` | 324.9 ns | 325.1 ns |
| `Text` from an existing String | 30.4 ns | 29.5 ns |
| Typed view body construction/destruction | 0.938 µs | handwritten: 0.947 µs |
| Hosting-view root replacement + synchronous layout | 0.309 ms | handwritten: 0.308 ms |
| Toggle + 1,000-row snapshot | **0.307 ms** | old ID-search snapshot: 0.849 ms |
| Toggle + 5,000-row snapshot | **1.460 ms** | old ID-search snapshot: 14.591 ms |

Results are medians, including harness overhead (about 1.6 ns for a trivial
value) and destruction. The Swift ABI reference functions are `@inline(never)`;
real Swift callers can optimize further. Values vary to resist constant folding,
and an external Zig optimization barrier consumes results. Inputs and key paths
are prepared outside timed sections. Cases run sequentially, so differences of
a few percent are not evidence of a meaningful advantage. Native and handwritten
view bodies have equivalent structure. The hosting benchmark measures CPU root
replacement/layout, not input latency, GPU composition or total display time.

**Typed generation has no measured material overhead in these cases.** It
produces ordinary concrete SwiftUI types. Direct ABI emission does not inherently
make SwiftUI faster: most wrappers are similar, and the generic environment path
is slower. Inspecting optimized Swift assembly shows that Swift specializes the
environment constructor into a key-path payload with a zero tag and a retain.
The Zig adapter deliberately still calls the framework's generic initializer.
A faster specialization could emit that representation directly, but should add
explicit representation checks and SDK-version coverage first. The current
factory benchmark exposes the cost instead of hiding it behind a view benchmark.

**The todo bottleneck was the algorithm across the boundary.** Each snapshot
row previously searched the entire Zig array for its title and completion flag,
making a refresh quadratic. The new `zw_todo_at` returns metadata and copies the
title by index. `TodoModel.refresh` now uses this linear path. The benchmark keeps
the old path as a reproducible baseline: 5,000-row snapshots are about **10×
faster**. Actual callback → Observation model refresh at 1,000 rows measures
0.292 ms. It still replaces the full array; per-item Observation and change diffs
are the next improvement. The core toggle alone is only 0.84 µs at 5,000 rows.

The copy-reduction iteration keeps the previous editor implementation in the
benchmark as `editor.snapshot_legacy`, alongside the current reducer. A second
[reference run](results/apple-m1-max-copy-reduction.json) measures both in one
process, forcing alternating, equal-sized edits on every operation:

| Document size | Previous reducer | Borrowed input + reused snapshot |
| --- | ---: | ---: |
| 1 KiB | 1.51 µs | 1.14 µs |
| 100 KiB | 0.115 ms | 0.106 ms |
| 1 MiB | 1.164 ms | 1.083 ms |
| 8 MiB | 9.234 ms | 8.711 ms |

Two small changes remove avoidable copies. The shared Swift `withUTF8` helper
borrows a contiguous UTF-8 buffer for the synchronous Zig call instead of creating
an Array and appending a terminator. Empty buffers still receive a valid address
for the nonnull C contract. Noncontiguous strings may require materialization;
the pointer never escapes the closure. Zig continues to copy data it retains.
After acceptance, `EditorReducer` reuses the input Swift String in its snapshot
instead of copying identical bytes back from Zig. This relies on `zw_editor_set`
accepting the exact bytes without normalization; tests check byte equality and
snapshot independence across subsequent edits.

The 8 MiB improvement was about 6% in this run. These measurements exclude
TextEditor's own editing/layout work and small timing differences remain noisy.
The core still copies its owned document and rescans it for statistics. Range-based
edits and incremental statistics could reduce that remaining cost, but require
more design than these changes. The current design is a small-document prototype.

## Verification and limits

Tested using Zig 0.16.0, Apple Swift 6.2.3, an ARM64 macOS 27.0.1 host and the
installed macOS 26.2 SDK. The lab targets macOS 26 minimum: the current major release (27) and its
immediate predecessor. `platform.zig` is the shared version source for Zig,
Swift, the ABI oracle and bundle metadata. macOS 26 has not been runtime-tested. Swift 6.2 is needed for the isolated
deinitializer used to tear down the callback context.

The original default app builds and all four original examples also compile
under 0.16. Their compile-only targets are named `check-<example-directory>`.
Verification transcripts are written to `zig-out/lab/verification-debug.txt`,
`verification-release.txt`, and `verification-examples.txt` in this workspace.

Automated coverage includes Zig allocation-leak checking, todo identity moves,
UTF-8 validation and bounded reads, statistics, callback masks, independent
stores, 10,000 native Text constructions/destructions, 1,000 model lifetimes,
Swift Observation notifications, installed DynamicProperty bindings, native
Bool/UInt64/Double/String state and Bool/Double environment propagation,
floating-point bit preservation (negative zero, NaN payload and infinity),
10,000 dynamic String/constant-binding lifetimes, generated keyed/conditional
identity, invalid view-program rejection and contextual diagnostics, borrowed
UTF-8 (empty/NUL/Unicode/NSString/large input), independent snapshot lifetimes,
UTF-8 FileDocument encoding, real
WebKit loads, and all three real Swift App entry points. Tests render PNGs in
`zig-out/lab/screenshots/`.

The loopback HTTP fixture additionally verifies that the real navigation delegate
blocks HTTP when disabled, then follows links, goes back/forward, and reloads
when enabled. This exposed a real title race: `WKWebView.title` can update after
`didFinish`. The browser now observes title, URL, loading, progress and history
properties instead of depending only on navigation callbacks. Both Debug and
ReleaseFast Zig builds are exercised; Swift is compiled with `-O` and warnings
as errors in both configurations.

The native computer-use service returned `cgWindowNotFound` when attaching to
the running app, even though the app's launch probe confirmed a visible window.
Physical mouse dragging and interactive Open/Save panels therefore remain
manual checks. Reordering logic and the file encoding path are tested directly.

These are prototypes: todos and browser state are in memory; the editor saves
only when requested and does not intercept window close to protect unsaved
edits. It confirms before replacing dirty text via Open. File imports are capped
at 8 MiB. Word counting uses ASCII whitespace; scalar counts are Unicode scalar
counts, not grapheme counts. There is no full browser tab/download/authentication
UI. C pointers are trusted internal handles, not a hardened third-party ABI.
All core calls are main-actor confined. Callbacks may read committed state but
must not recursively mutate or destroy their store.

## Next steps and alternative paths

1. **Expand typed source generation.** Named state, environment, bindings,
   branches and keyed components now work. Next add schema-derived model types,
   typed custom environment keys, richer action parameters, nested keyed scopes,
   and source-location links from Swift diagnostics to Zig definitions. Keep swiftc responsible for
   conformances, key paths, reflection metadata and result-builder types.
2. **For application robustness: keep the generated C boundary.** Add structured
   error codes, batched diffs, multiple observer tokens and an explicit scheduling
   contract. Publish per-item Observation changes instead of copying every row.
   Use `DocumentGroup` for the editor's document lifecycle; use a rope/piece table
   and incremental statistics for large documents. Persist todos with a versioned
   format and atomic writes.
3. **For runtime-defined UI: a Zig node tree plus a Swift renderer.** Send a tagged
   tree with stable keys and action IDs across the boundary. It handles Zig loops
   and branches naturally, but broad `AnyView` erasure can weaken structural
   identity and optimization. Define identity rules before adding many controls.
4. **For deeper ABI research: add specializations one at a time.** The registry now emits a
   manifest and CFI, checked against compiler IR. Next add cross-version CI,
   assembly-level register/ownership checks, and unwinding tests. Useful next
   signatures are `State<Optional<String>>`, `Binding<String>.constant`, and
   closure-backed bindings; optionals and capturing closures need their own
   ownership/lowering work. A real Swift-ABI backend would also need value/protocol witness tables,
   resilient layouts, closure contexts, exclusivity and concurrency conventions.
   The current ten entry points do not generalize automatically.
5. **If a tiny non-Zig shim is acceptable:** a Swift `@_cdecl` adapter, or a
   Clang `swiftcall` shim, can let a compiler handle lowering instead of handwritten
   ARM64. Swift source generation is the more direct choice for SwiftUI generics.
6. **Use the current platform baseline:** Apple's [WebKit for SwiftUI](https://developer.apple.com/documentation/webkit/webkit-for-swiftui)
   provides `WebView`/`WebPage`, reducing the representable/delegate code. This lab
   still uses `WKWebView`; its macOS 26 minimum now permits this simplification.

During migration, Zig 0.16 required `@Tuple`/`@Fn` in place of the old `@Type`
construction and moved object linking onto the root module. The package name
checksum was stale after the earlier `zwift` rename; its random identity bits
were preserved while updating that checksum. See the [0.16 release notes](https://ziglang.org/download/0.16.0/release-notes.html).
Swift 6.2.3 also crashed during IR generation for a bound method passed directly
as a Binding setter; spelling it as `set: { replace($0) }` compiled successfully.

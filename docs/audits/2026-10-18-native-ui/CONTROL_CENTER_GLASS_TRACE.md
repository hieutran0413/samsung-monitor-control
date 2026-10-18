# Control Center glass: static trace

Checked 2026-10-18 on macOS 27.2, build 26B5112a. Read-only inspection of the installed Apple executable; no debugger attachment, injection, private-API invocation, system modification or app glass change was used for this trace.

## Finding

The Control Center executable imports a dedicated **private SwiftUI `_Glass.controlCenter`** variant and a separate **`_Glass.slider`** variant. It imports the private `_glassEffect` view modifier. Consequently there is concrete evidence of a Control Center-specific glass API; claiming its appearance is simply the public `Glass.regular` or `Glass.clear` is unsupported.

This is static binary evidence, not a recovered implementation of each widget. The executable also imports `_Glass.regular` and `_Glass.explicit(Material)`. An import does not identify every call site, a subvariant string, tint, mix amount, adaptive setting, or which exact module uses it. No claim that every surface uses one variant is made.

## Reproduction and evidence

Executable: `/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter`.

Run:

```sh
nm -arch arm64e -u /System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter \
  | xcrun swift-demangle \
  | rg 'SwiftUI\._Glass|SwiftUI\.Glass\.'
```

Relevant imported demangled symbols:

```text
static SwiftUI._Glass.controlCenter.getter : SwiftUI._Glass
static SwiftUI._Glass.slider.getter : SwiftUI._Glass
static SwiftUI._Glass.regular.getter : SwiftUI._Glass
static SwiftUI._Glass.explicit(SwiftUI.Material) -> SwiftUI._Glass
static SwiftUI._Glass.identity.getter : SwiftUI._Glass
SwiftUI._Glass.subvariant(Swift.String?) -> SwiftUI._Glass
SwiftUI._Glass.interactive(Swift.Bool) -> SwiftUI._Glass
SwiftUI._Glass.forceSubdued(Swift.Bool) -> SwiftUI._Glass
SwiftUI._Glass.mix(with: SwiftUI._Glass, by: Swift.Double) -> SwiftUI._Glass
SwiftUI._Glass.adaptive(Swift.Bool) -> SwiftUI._Glass
SwiftUI._Glass.tintColor(SwiftUI.Color?) -> SwiftUI._Glass
```

The same import list contains `SwiftUI.View._glassEffect(_: SwiftUI._Glass, in:)`, `GlassEffectContainer`, and `glassEffectID`. Separate strings identify `BentoBackdrop`, `BentoBackdropModifier`, `ModuleBackdropModifier`, `ControlCenterApp/WindowBackdrop.swift`, and `CABackdropLayer`. `otool -L` shows the private ControlCenter framework dependency alongside public SwiftUI/AppKit. These corroborate a custom system composition but do not disclose its full recipe.

## Product implication

The public SwiftUI API documented by Apple exposes regular and clear glass; it does not expose `_Glass.controlCenter` or `_Glass.slider`. See [Apple materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials) and [adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass).

The app's public `.regular` implementation is therefore an approximation using supported APIs, not proof of parity with Apple's Control Center. Renaming it “small” or “medium”, repeatedly toggling `.regular`/`.clear`, or adding an arbitrary dark overlay does not reproduce this private variant. Any later decision to experiment with underscored/private SwiftUI APIs must be explicit, version-gated and separately verified; this trace adds no such dependency to the app.

Still unknown: per-widget variant call sites, subvariant values, actual layer/filter parameters, appearance adaptation, slider drag recipe and runtime composition. Those require deeper call-site/runtime investigation; they cannot be inferred from a screenshot or these imports alone.

## Authorized local experiment

The user explicitly selected “Thử private trên máy này”. The app now resolves `_Glass.controlCenter` at runtime through the isolated `PrivateControlCenterGlass.swift` bridge. On this exact OS build, the public `Glass` wrapper has one `_Glass` base and a 40-byte, 8-byte-aligned indirect-return layout. An isolated executable called the private regular getter and verified equality with public `Glass.regular` before calling the controlCenter getter. Reflection showed `_Glass(controlCenter)`, distinct from regular; the installed app emitted `QC_GLASS=private.controlCenter`.

This is an unsupported Swift ABI bridge, not a source-level public API. It is allowed only on build `26B5112a`; different builds, missing symbols, a different wrapper shape/size, or a failed regular-equivalence check use public regular. The OS build restriction is essential: runtime checks cannot make an unknown ABI safe. Do not expand the allowlist without a separate process probe. `SMC_PUBLIC_GLASS=1` forces the public fallback; this path was verified in the probe. No system binary was modified or injected.

Computer Use captured the installed overview with the private variant: the surfaces became lighter, with the Control Center-like perimeter highlight and visible white labels. This verifies an observable rendering change, not pixel parity with Control Center. A subsequent submenu interaction was interrupted by the tool reporting that the user changed the app, followed by an app-state timeout; this attempt does not verify private-material navigation/morphing. The existing native slider/thumb is unchanged and is not represented as `_Glass.slider`.

Following the user's request “màu text vibrant, plus lighter”, foreground text/icons use white with SwiftUI `BlendMode.plusLighter` **before** the glass modifier, so the content layer composites additively while the glass material itself is retained. This is the requested compositing treatment; it is not a claim that AppKit system vibrancy and every Control Center foreground recipe have been reconstructed.

Subsequent QC on the Plus Lighter build successfully captured overview and Display detail, then clicked Back and confirmed overview returned. This supersedes the earlier interaction timeout for that flow. No video/frame-time measurement of morph animation was taken. The installed build succeeded and the existing 10 Python tests remained passing; these tests are unrelated to glass rendering.

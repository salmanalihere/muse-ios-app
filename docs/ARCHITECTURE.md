# Foldfleet — Milestone 1: Architecture Report
Date: 26 October 2026 · Checked against live sources on this date

## 1. The headline finding — the device is real, and it just launched

iPhone Duo is real. Apple announced it 9 September 2026, opened pre-orders
16 October, and put it on sale **23 October 2026 — three days ago** — starting
at **$1,999** (256 GB).

- Inner display: 7.6-inch Super Retina XDR OLED, **1878 × 2670, 430 ppi**,
  nano-texture finish, ProMotion to 120 Hz
- Outer display: 5.4-inch Super Retina XDR OLED, **1398 × 2034, 460 ppi**
- Chip: A20 Pro · 12 GB RAM · 254 g · 5.2 mm open / 11.3 mm closed · IP68
- Unlock: Touch ID in the side button — **no Face ID**
- Ships with **iOS 27.1**

Sources: Apple, “iPhone Duo – Technical Specifications”
(apple.com/ca/iphone-duo/specs); Apple Developer News, 5 Oct 2026,
“Prepare and submit your apps for iPhone Duo”
(developer.apple.com/news/?id=kkphp5qo).

## 2. The toolchain — verified

| Item | Verified value |
|---|---|
| Xcode | **27.1, build 27A9275**, released 15 Oct 2026 |
| Swift | **6.4** |
| SDK | **iOS 27.1** (plus iPadOS 27, macOS 27, tvOS 27, watchOS 27, visionOS 27) |
| Mac required | Apple-silicon Mac running **macOS Tahoe 26.6 or later**. Xcode 27 does not run on Intel Macs. |
| App Store | App Store Connect has accepted Xcode 27.1 / iOS 27.1 uploads since 5 Oct 2026. Apps built with it get an “Optimized for iPhone Duo” badge when Duo screenshots are submitted. **From April 2027, every submission must include iPhone Duo screenshots.** |
| Duo Simulator | In Xcode 27.1 only, via **Device Hub** — open, close, rotate and fold the simulated Duo and watch the app react in every pose. Known limits in 27.1: StandBy and most app extensions are unavailable in the Duo Simulator runtime. |

Sources: Apple Developer News (above); Mac Observer, “Xcode 27.1 is out with
Swift 6.4” (19 Oct 2026); Blake Crosley, “Xcode 27 is out” / “Prepare your
app for iPhone Duo”.

## 3. Hinge / fold APIs — what is real, and what is not yet in the reference

This is the part the brief asked me not to invent. Here is the honest split.

### Verified in Apple’s iOS 27.1 SDK / Tech Talks

- **`ArrangementView`** (SwiftUI, iOS 27.1 / iPadOS 27.1) and
  `UIArrangementViewController` (UIKit). A layout container holding a primary
  and a secondary view. `.split` places them side by side and adapts its axis
  to the space; `.split.axes(.horizontal)` forces a horizontal split;
  `.overlay` stacks them. Foldfleet uses `.split.axes(.horizontal)` for the
  battle screen. Do not put a `NavigationSplitView`, `List` or `ScrollView`
  inside an `ArrangementView`.
- **`reservedRegions(kind:options:)`** — on `GeometryProxy` in SwiftUI and on
  `UIView` in UIKit. Kinds: **`.division`** (the fold) and **`.occlusion`**
  (the under-display FaceTime camera). A division region **is active only
  when the device is folded, and has zero width when flat**; pass
  `.includeInactive` to still learn where the fold *would* be, e.g. to choose
  an even number of grid columns so a future fold never bisects a cell.
  Foldfleet reads the division region (including inactive) and keeps a
  minimum 24 pt gutter around it — no button or essential information sits
  on the crease.
- **Hinge state — `.onHingeChange` (SwiftUI) / `UIHingeInteraction` (UIKit).**
  Reports three statuses — `.closed`, `.partiallyOpen`, `.fullyOpen` — plus a
  continuous hinge angle. A `nil` hinge means the device has no hinge.
  Apple’s own Tech Talk examples use this shape:
  `.onHingeChange { _, context in if let hinge = context.hinge … }`.
- **Size classes are the primary layout signal.** Outer display: compact
  width. Inner display: **regular width, regular height, in both portrait
  and landscape**. Apple’s guidance, repeated in the Platforms State of the
  Union: stop designing for specific devices / fixed orientations; target “a
  dynamic range of sizes and aspect ratios”. Foldfleet therefore branches on
  size class + available geometry, never on a device name or a pixel width.
- **Scene lifecycle is required** when linking iOS 27. Do not use
  `UIScreen.main` (deprecated) — use the window scene / trait collection /
  `windowScene.effectiveGeometry`. `UIRequiresFullscreen` is honoured on
  iPhone in iOS 27, but only as discrete resizing — it no longer opts an app
  out of resizing.
- **iOS 27 framework strings `foldState` / `angleDegrees`** were found in the
  iOS 27 beta (June 2026, Sam Henri Gold, confirmed by Macworld / 9to5Mac).
  Those are *internal framework strings*, not a public API to call. Do not
  use them.

### NOT verified — do not rely on these

- A dedicated developer.apple.com/documentation page for `onHingeChange` /
  `UIHingeInteraction` / `ArrangementView` was **not found by search** as of
  27 Oct 2026. The Tech Talk above is the authoritative source so far.
  Foldfleet isolates all hinge code in one file,
  `Foldfleet/Views/DuoLayout.swift`, with a size-class fallback that works
  with no hinge at all. **First job on the cloud Mac: open that file in
  Xcode 27.1, let autocomplete confirm the signature, and fix it there.
  The game must never depend on the hinge callback to be playable.**
- Whether the SwiftUI hinge-status enum also has a `.unknown` case (the
  UIKit `UIHinge` enum is reported to include one). `DuoLayout.swift`
  handles it with `@unknown default`, so either way it compiles.
- The exact `reservedRegions` overload spelling (`.includeInactive` as a
  single option vs. `[.includeInactive]`). Both appear in Apple-derived
  examples; Xcode autocomplete is the final check.
- No official Apple documentation was found giving the Duo’s exact hinge
  width in points, the exact crease gutter, or a “tabletop posture” API.
  Foldfleet does not hard-code those numbers; it measures the division
  region at runtime and adds its own 24 pt margin.
- No third-party framework is needed, and none is used. Standard SwiftUI +
  UIKit only. That keeps App Store review simple.

### Re-checked 27 Oct 2026 — hinge signature upgraded

Apple Tech Talk 111464 ("Leverage multiple displays and scenes on iPhone
Duo", developer.apple.com/videos/play/tech-talks/111464/) confirms, in
Apple's own words and example code, that SwiftUI provides `.onHingeChange`
and UIKit provides `UIHingeInteraction`, both reporting `.closed` /
`.partiallyOpen` / `.fullyOpen` plus continuous hinge angle, with a nil
hinge meaning no hinge, and that the modifier's closure takes the previous
and the current hinge context: `.onHingeChange { _, context in if let
hinge = context.hinge … }` — exactly the shape used in `DuoLayout.swift`.
Apple's guidance is explicit: hinge data is for interactions/effects, not
layout; layout comes from arrangements and reserved regions. Foldfleet
follows that: the hinge callback only records state, layout never depends
on it.

## 4. What can be done on Windows, and what cannot

| Task | Where |
|---|---|
| Write / edit all Swift, project and docs files | **Windows — yes, here** |
| Check game rules with the Python mirror in `scripts/verify_logic.py` | **Windows / this VM — yes** |
| Install Swift for Windows (swift.org toolchain) and compile the *pure logic* files as a command-line check | Windows — yes, optional; it cannot build SwiftUI / UIKit |
| Run Xcode, iOS Simulator, Duo Simulator / Device Hub | **Mac only — no** |
| Build, sign, TestFlight, App Store submission | **Mac only — no** |
| Test on a real iPhone Duo | Real device only — not done yet |

Xcode runs only on macOS, under Apple’s licence. Running macOS in a VM on a
Windows PC violates that licence and is fragile — not recommended for a
release build. The compliant routes are: a used / borrowed Apple-silicon Mac,
or a cloud Mac (MacinCloud from ~$30/mo, MacStadium, AWS EC2 Mac), or a
macOS GitHub Actions runner for CI builds. See `README.md` § Windows workflow.

## 5. Architecture chosen

```
Foldfleet (SwiftUI app, iOS 27.1, Swift 6.4, Xcode 27.1)
├── Models/GameModel.swift      Pure rules. No SwiftUI, no UIKit. Fully unit-testable.
│   ├── Coordinate, ShipType, Ship, Fleet, ShotResult, GamePhase
│   └── GameState: placement, fire(), sunk / win detection, turn rules
├── Models/AIPlayer.swift       Easy (random) / Normal (hunt+target) / Hard (probability density)
│                               Uses ONLY the shot history — never the hidden fleet.
├── Models/Persistence.swift    Stats + match history (JSON in Documents) + Settings (@AppStorage)
├── Models/SoundEngine.swift    Synthesised sounds (AVFoundation oscillators) — no copyrighted audio
├── ViewModels/GameViewModel.swift  @Observable glue: GameState + AI turn + haptics + sounds
├── Views/DuoLayout.swift       THE Duo file: ArrangementView, reservedRegions, onHingeChange,
│                               size-class fallback. Everything else just asks it “wide or narrow?”
├── Views/OceanGridView.swift   One reusable 10×10 grid, accessible, colour+shape coded
├── Views/PlacementView.swift   Tap-to-place + rotate + randomise (drag is optional, never required)
├── Views/BattleView.swift      Two-zone battle: own fleet left, enemy waters right (wide);
│                               single-pane with a Fleet / Target switcher (narrow / cover display)
├── Views/MenuView.swift, SettingsView.swift, HelpView.swift, HistoryView.swift,
│   HandoffView.swift, EndGameView.swift
└── FoldfleetTests/             XCTest: placement, overlap, edges, hits/misses, repeats,
                                sinking, victory, AI validity, save/restore, handoff privacy
```

Principles: game rules live in one testable model, never in views; the AI
cannot see hidden ships; all Duo behaviour is isolated so a signature change
in Xcode touches one file; no accounts, no trackers, no ads, no network in
v1 — fully offline; no secrets in source.

## 6. Layout decision (deliberate)

- **Best experience: inner display, landscape, fully open.** Two 10×10
  grids side by side, own fleet left, enemy right, with the fold gutter
  between them.
- **Cover display / portrait / compact width:** single pane. A segmented
  switcher flips between “Your Fleet” and “Enemy Waters”. Nothing is lost,
  nothing is squeezed.
- **Partially open (laptop / tent pose):** the game does not invent a
  special mode. It keeps the same layout, driven by size class and geometry.
  The hinge callback only records the hinge state for information — it does
  not change the layout, the rules, or hide a grid.
- Orientation is not locked. The game is playable in portrait; landscape
  is recommended on the inner display and the Help screen says so.

## 7. Known limitations (honest list)

1. **Not compiled in Xcode yet.** No Swift toolchain exists in this
   environment, and there is no Mac here. The Swift files are written
   carefully against the iOS 27.1 SDK as documented, but the first
   `xcodebuild` on a cloud Mac is the real compile check. The Python mirror
   (`scripts/verify_logic.py`) validates the *rules*, not the Swift syntax.
   (27 Oct 2026: the pure-logic files — GameModel, AIPlayer, Persistence —
   were compiled and tested with Swift 6.2.1 on Linux, see README. The
   SwiftUI / UIKit / AVFoundation files still need Xcode.)
2. **Hinge API signature** — confirmed via Apple Tech Talk 111464 (see §3),
   but a dedicated API-reference page was not found. Xcode 27.1
   autocomplete is still the final check, in `DuoLayout.swift` only.
3. **Not tested on a real iPhone Duo**, in the Duo Simulator, or with
   VoiceOver on device. Simulator + device testing is Milestone 7 and is
   still open.
4. **Sounds are synthesised**, not recorded. They are original, but simple.
5. **Online multiplayer is NOT built** (Milestone C, later phase, by design).
   No fake multiplayer UI is included.
6. App icon is a generated placeholder (naval anchor / waves, drawn in code
   as an asset catalogue entry) — replace with a final designed icon before
   submission. Bundle ID is the placeholder `com.foldfleet.game`.
7. Duo screenshots are required from April 2027 — not yet produced; they
   need the Duo Simulator.

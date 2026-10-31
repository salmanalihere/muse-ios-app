# Foldfleet

A premium, native naval strategy game for **iPhone Duo** — Apple's first
folding iPhone (launched 23 Oct 2026, $1,999, iOS 27.1).

Open the Duo flat: **your fleet on the left, enemy waters on the right**,
with nothing important on the fold. On the cover display, or in portrait,
switch between the two with one tap.

Solo against three levels of AI, or local pass-and-play for two players on
one phone. Fully offline. No account, no ads, no trackers.

> **Status: Milestones 1–6 implemented as source. Pure Swift logic now
> compiles and passes tests on Linux (Swift 6.2.1) — see “What was actually
> checked”. The full iOS app (SwiftUI / UIKit / AVFoundation) has NOT yet
> been compiled in Xcode, and has NOT been tested on a real iPhone Duo.**
> This app is **not release-ready** until it builds and passes tests in Xcode.

## Milestone 1 — what was verified (26 Oct 2026)

Full report: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

- **Device is real:** iPhone Duo, inner 7.6" 1878×2670, outer 5.4" 1398×2034,
  A20 Pro, Touch ID, $1,999, on sale 23 Oct 2026.
  Apple specs: https://www.apple.com/ca/iphone-duo/specs/
- **Toolchain:** Xcode **27.1 (27A9275)**, Swift **6.4**, iOS 27.1 SDK.
  Requires an Apple-silicon Mac on macOS Tahoe 26.6+.
  App Store Connect accepts Xcode 27.1 builds; Duo screenshots become
  mandatory for submissions from **April 2027**.
  Apple Developer News: https://developer.apple.com/news/?id=kkphp5qo
- **Fold APIs (iOS 27.1):** `ArrangementView` (`.split.axes(.horizontal)`),
  `GeometryProxy.reservedRegions(kind: .division / .occlusion,
  options: .includeInactive)`, `.onHingeChange` / `UIHingeInteraction`
  (closed / partiallyOpen / fullyOpen + continuous angle, `nil` = no hinge).
  Layout branches on **size class + geometry**, never on a device name.
- **Hinge signature — upgraded 27 Oct 2026:** Apple Tech Talk 111464
  ("Leverage multiple displays and scenes on iPhone Duo",
  developer.apple.com/videos/play/tech-talks/111464/) confirms
  `.onHingeChange { _, context in if let hinge = context.hinge … }` with
  `hinge.status` and `hinge.angle.degrees`, and that hinge data is for
  interactions/effects, not layout. A dedicated API-reference page for
  `onHingeChange` was still not found by search, so Xcode 27.1 autocomplete
  remains the final check, in `DuoLayout.swift` only. See
  [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) §3 for the confirmed /
  not-yet-confirmed split.

## 27 Oct 2026 audit — what was fixed

Every Swift file and the Xcode project were re-read. Fixes, in order:

1. **Compile error (confirmed):** `GameState.randomFleet(using:)` used
   unqualified `gridSize` twice. Fixed to `GameModel.gridSize`.
2. **AI wasted shots on sunk ships:** Normal and Hard targeted around ALL
   hits, including sunk ships. Added `ShotHistory.sunkShots` /
   `activeHits`; Hard now also refuses placements covering a sunk ship.
   The AI still only sees shot history — never hidden ship positions.
3. **Invalid taps advanced the game:** an already-shot tap in solo
   scheduled the AI and in pass-and-play showed the handoff screen.
   `GameViewModel.fire()` now only advances on a real hit / miss / sunk.
4. **Pass-and-play showed the wrong fleets:** BattleView always showed
   Player 1's fleet as "your fleet". It now uses `ownFleet` / `enemyFleet`
   for whoever is about to shoot. This was also a privacy leak.
5. **Pass-and-play placement had no handoff screen:** Player 2's placement
   started immediately. PlacementView now shows the handoff sheet, and
   battle start hands the phone back to Player 1.
6. **Resume could deadlock / lose stats:** resuming a solo game on the AI's
   turn waited forever for a tap the player cannot make, and shot counts
   reset to zero. Added `GameViewModel.restoreSavedGame(_:)`, which
   recomputes shot counts and schedules the AI turn when needed.
7. **Rematch stayed on the battle screen:** it reset the model but never
   left battle, and always started a solo game. Rematch now starts a fresh
   match in the same mode and returns to placement.
8. **Swift 6 concurrency:** `Persistence` and `SoundEngine` are now
   `@MainActor` (all callers already were), the AI task hops back via
   `MainActor.run`, and the arpeggio / audio-detach callbacks use MainActor
   tasks instead of DispatchQueue.
9. **Dead / misleading UI removed:** the Settings "ambience / music" toggle
   did nothing (there is no looping track) — removed. EndGameView showed
   solo stats after a pass-and-play match — now shows the right stats.
   Removed unused state in MenuView / BattleView / PlacementView, and the
   dead `remainingLengths` code in `AIPlayer`.
10. **Assets:** added the missing `AccentColor` colour set that the Xcode
    project references, and cleaned the AppIcon contents (it had duplicate
    entries).

New tests added (see `FoldfleetTests/`): fire before battle, fire outside
the grid, repeat shot does not change the turn, moving a ship replaces it,
save/restore preserves winner and phase, seeded random fleet, coordinate
labels, AI ignores sunk ships (Normal and Hard).

## What was actually checked

| Check | Result |
|---|---|
| Game rules — Python mirror, `scripts/verify_logic.py` | **27 passed, 0 failed** (27 Oct 2026) |
| Swift logic — typecheck, Linux Swift 6.2.1 | **OK** — `GameModel.swift`, `AIPlayer.swift`, `Persistence.swift` typecheck in Swift 6 language mode |
| Swift logic — harness, `scripts/swift_check/run.sh` | **28 passed, 0 failed** (Linux Swift 6.2.1) |
| Swift XCTest — actual `FoldfleetTests/`, Linux Swift 6.2.1 via SwiftPM | **42 tests, 0 failures** — 20 GameModelTests + 9 AIPlayerTests + 13 TrialManagerTests (trial + access rules) |
| Xcode compile (SwiftUI / UIKit / AVFoundation files) | **NOT run — Mac only.** First `xcodebuild` is still the real check. |
| StoreKit purchase flow | **NOT run — Mac only.** Local testing needs Xcode 27.1 + `Foldfleet.storekit` (see `docs/STOREKIT.md`). |
| iOS XCTest in Xcode | **NOT run — Mac only.** Run on a cloud Mac, or via the GitHub Actions workflow in `.github/workflows/xcode-build.yml` (it selects Xcode 27.1 explicitly — the `xcode-27` runner defaults to 27.0): `xcodebuild test -scheme Foldfleet -destination 'platform=iOS Simulator,OS=27.1,name=iPhone Duo'` |
| Duo Simulator / real Duo | **Not done yet.** Milestone 7. |

Notes on the Swift checks above: they used Swift **6.2.1 on Ubuntu 24.04**,
not Swift 6.4 / Xcode 27.1, and they cover only the pure-logic files
(`GameModel`, `AIPlayer`, `Persistence`, `TrialManager`).
SwiftUI, UIKit, AVFoundation and StoreKit do not exist on Linux, so those
files were inspected by hand only. The Linux XCTest run is real XCTest, but
it is not a substitute for the Xcode iOS run.

## 27 Oct 2026 — 5-minute trial + one-time unlock (StoreKit 2)

Free to download, 5 minutes free, then **Unlock Foldfleet — $14.99**,
one-time Non-Consumable (`com.foldfleet.fullgame`), StoreKit 2 only.
Full detail: [`docs/STOREKIT.md`](docs/STOREKIT.md).

- The trial starts when a game starts (not on launch), lasts 5 minutes of
  real elapsed time, is stored as one persisted timestamp
  (`foldfleet.trialStartDate`), and is shared by Solo and Pass-and-Play.
  Backgrounding, quitting or restarting never pauses or resets it.
- While a trial runs, Placement and Battle show a subtle
  `Free Trial · 4:32` indicator. The menu never shows it.
- When the trial expires, the paywall appears ("Your Free Trial Has
  Ended"), the current battle is left intact, and no new game, shot or AI
  turn is allowed until the game is unlocked.
- The game unlocks only on a **verified** StoreKit transaction; Restore
  Purchase re-checks entitlements and never charges. Owners never see the
  trial, timer or paywall.
- Local testing: `Foldfleet.storekit` in the project root — select it in the
  Xcode scheme (Run → Options → StoreKit Configuration). The product does
  not exist in App Store Connect yet; creating it is a separate step on a
  Mac (see `docs/STOREKIT.md`).
- No gameplay rules, Duo layout, hinge code or pass-and-play flow changed.
  No existing test was weakened or deleted; 13 trial tests were added.

One real bug was caught by the mirror test and fixed in the Swift code too:
shots after game-over returned `.invalid` instead of `.gameOver` because the
phase check ran first. `GameModel.fire()` now checks game-over first.

## Project layout

```
Foldfleet.xcodeproj/          Xcode 27.1 project (bundle id com.foldfleet.game — placeholder)
Foldfleet/
  Models/GameModel.swift      Pure rules: 10×10, 5/4/3/3/2 fleet, fire/sink/win
  Models/AIPlayer.swift       Easy random / Normal hunt+target / Hard probability density
  Models/Persistence.swift    Local JSON stats + history + saved game (corrupt file = fresh start)
  Models/TrialManager.swift   5-minute free trial (persisted timestamp) + access rules
  Models/StoreManager.swift   StoreKit 2: product, purchase, entitlements, restore
  Models/SoundEngine.swift    Synthesised sounds, no copyrighted audio
  ViewModels/GameViewModel.swift  Placement, AI turns, haptics, saving, match recording
  Views/DuoLayout.swift       THE Duo file: ArrangementView, reserved regions, hinge
  Views/OceanGridView.swift   Reusable grid, colour + shape + VoiceOver labels
  Views/MenuView.swift        App entry, menu, stats
  Views/PlacementView.swift   Tap-to-place, rotate, randomise (no drag required)
  Views/BattleView.swift      Two-zone battle, handoff, end-of-match
  Views/PaywallView.swift     "Your Free Trial Has Ended" unlock screen
  Views/SettingsHelpHistory.swift
  Views/DesignSystem.swift    Deep ocean + brass design system
FoldfleetTests/               GameModelTests.swift, AIPlayerTests.swift, TrialManagerTests.swift
Foldfleet.storekit            StoreKit Configuration file for local purchase testing
docs/ARCHITECTURE.md          Milestone 1 report
docs/PRIVACY.md               Data disclosure for App Store
docs/STOREKIT.md              Trial + purchase: mechanics, verification, test checklist
docs/RELEASE_CHECKLIST.md     Milestone 8 checklist
docs/TESTING.md               Test plan (Milestone 7)
scripts/verify_logic.py       Python rule mirror — run anywhere
scripts/swift_check/          Swift logic harness (main.swift + run.sh) — needs a Swift toolchain
scripts/windows_setup.ps1     Windows setup commands
```

## Checking the logic without a Mac

```bash
# Python mirror (no Swift needed):
python3 scripts/verify_logic.py
# Expected: 27 passed, 0 failed

# Real Swift compile + harness (needs swiftc on PATH — Linux Swift 6.2+
# from swift.org, or macOS Xcode CLI tools):
bash scripts/swift_check/run.sh
# Expected: typecheck OK, then 28 passed, 0 failed

# Real XCTest, same logic files (needs swiftc + SwiftPM):
#   copy Sources/ + Tests/ into a Swift package as in docs/TESTING.md,
#   then: swift test
# Expected on Linux Swift 6.2.1: 42 tests, 0 failures
```

## Windows workflow (you, on Windows 11)

You cannot run Xcode on Windows. That is a hard Apple limit, not a missing
install. What you **can** do on Windows:

```powershell
# 1. Unzip Foldfleet.zip, open the folder in VS Code
# 2. Check the game rules (no Mac needed):
python scripts/verify_logic.py
# 3. Optional: install Swift for Windows to syntax-check the pure logic files
#    (it cannot build SwiftUI / UIKit / iOS):
winget install Swift.Toolchain
# 4. Edit Swift files in VS Code with the Swift extension
# 5. Push to GitHub, then build on a cloud Mac (below)
```

See [`scripts/windows_setup.ps1`](scripts/windows_setup.ps1) for the exact commands.

## Mac-only steps (cloud Mac)

1. Rent a cloud Mac — MacinCloud (~$30/mo), MacStadium, or AWS EC2 Mac —
   or use a macOS GitHub Actions runner. Do **not** run macOS in a VM on
   your Windows PC for a release build (licence + fragility).
2. On the Mac: install **Xcode 27.1** from the App Store / Apple Developer.
   Check: `xcodebuild -version` → `Xcode 27.1 Build version 27A9275`.
3. Open `Foldfleet.xcodeproj`. Fix `DuoLayout.swift` first — let Xcode
   autocomplete confirm `.onHingeChange`.
4. Run the tests:
   ```bash
   xcodebuild test -scheme Foldfleet -destination 'platform=iOS Simulator,OS=27.1,name=iPhone Duo'
   ```
   (Pin `OS=27.1`: the iOS 27.1 runtime only supports the iPhone Duo. If the Duo device type is missing, download the iOS 27.1 platform first with `xcodebuild -downloadPlatform iOS` under Xcode 27.1.)
5. Run in the **iPhone Duo Simulator** (Device Hub in Xcode 27.1): open,
   close, fold, rotate. Check no button sits on the crease, grids stay
   readable, and the game survives a fold mid-battle.
6. TestFlight, then App Store — see [`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md).

## How to play

1. New Solo Battle → pick a difficulty → place your 5 ships (tap a ship,
   tap a cell, Rotate / Randomise if you like) → Begin battle.
2. Tap a cell in Enemy Waters to fire. Burst = hit, drop = miss,
   red octagon = sunk.
3. Sink all 5 enemy ships first to win.
4. Pass-and-Play: after each turn a handoff screen hides the fleets until
   the next player taps Ready.

## Privacy

Offline v1. Only settings, match history and local stats are stored, on the
device only. No account, no ads, no analytics, no network. Full text:
[`docs/PRIVACY.md`](docs/PRIVACY.md)

## Known limitations

- **Not release-ready.** The full iOS app has not been compiled in Xcode
  yet. SwiftUI / UIKit / AVFoundation files were inspected by hand only;
  the Linux Swift checks cover the pure-logic files. First `xcodebuild`
  on a cloud Mac is the real compile check.
- Hinge API: signature confirmed via Apple Tech Talk 111464, but no
  dedicated API-reference page was found; Xcode 27.1 autocomplete is the
  final check, in `DuoLayout.swift` only. The `reservedRegions` overload
  spelling (`.includeInactive` vs `[.includeInactive]`) is also unconfirmed
  until Xcode checks it, and the SwiftUI hinge-status enum may have an
  extra `.unknown` case (handled with `@unknown default`).
- Not tested on a real iPhone Duo or in the Duo Simulator.
- Sounds are synthesised, not recorded. No looping ambience/music track.
- App icon is a generated placeholder — replace before submission.
- Online multiplayer is intentionally **not** built (later phase).
- Bundle ID `com.foldfleet.game` is a placeholder — choose a permanent one
  before submission.

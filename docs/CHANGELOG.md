# Foldfleet — Changelog

## 27 Oct 2026 — Fix: AVAudioEngine crash on iPhone Duo simulator

Crash reported on CoreSimulator, iOS 27.1, iPhone Duo:
`Terminating app due to uncaught exception 'com.apple.coreaudio.avfaudio',
reason: 'required condition is false: inputNode != nullptr || outputNode != nullptr'`

Root cause: `SoundEngine.play()` called `engine.start()` in a Swift
do/catch, which cannot catch this NSException, and `tone()` / `noise()`
read `engine.mainMixerNode.outputFormat(forBus: 0)` before the engine was
known to be running. On a simulator with no audio output device, the
engine graph has no input/output node, so that trips the assertion.

Fix — only `Models/SoundEngine.swift` changed, no gameplay, layout,
hinge, pass-and-play, trial or StoreKit code touched:
- Simulator: sounds are now a no-op (`#if targetEnvironment(simulator)`).
  The game plays silently instead of crashing. Real-device sound is unchanged.
- Real device: check `AVAudioSession.currentRoute.outputs` first; if empty,
  latch audio as unavailable and never call `engine.start()`.
- Configure the session (`.ambient`, `.mixWithOthers`) and activate it
  before starting, with Swift errors caught.
- Buffers now use a fixed `AVAudioFormat(standardFormatWithSampleRate: 44100,
  channels: 1)` instead of the mixer format, and no force-unwraps remain
  on buffers / channel data. `playBuffer()` only touches the mixer after
  the engine is running.
- Public API unchanged: `SoundEngine.shared.play(_:enabled:)` and all
  callers are untouched.

Verification: I cannot compile AVFoundation code on this Linux machine
(no Swift toolchain here, and SoundEngine needs Xcode 27.1 on a Mac), so
this fix is NOT yet verified by a build. Retest on the Duo simulator:
launch, tap to place / fire, and use Settings > Play sonar test — the app
must not crash, and it will be silent on the simulator by design. Sound
on a real iPhone Duo still needs a device test.

## 27 Oct 2026 — 5-minute trial + one-time unlock (StoreKit 2)

Implemented at Salman's explicit request. Free to download, 5 minutes free
gameplay, then **Unlock Foldfleet — $14.99**, one-time Non-Consumable
(`com.foldfleet.fullgame`), StoreKit 2 only. No other payment system.

- New: `Models/TrialManager.swift` — persisted-timestamp trial (starts only
  when gameplay starts; elapsed wall-clock time, so backgrounding /
  termination / relaunch never pause or reset it; one trial shared by Solo
  and Pass-and-Play; no reset API). Plus `GameAccess`, the single pure
  access rule (owner / trial running / trial expired).
- New: `Models/StoreManager.swift` — product load, purchase, entitlements
  (`Transaction.currentEntitlements` is the authority, refunds revoke),
  restore (`AppStore.sync()`), transaction listener from launch. Unlocks
  only on a **verified** transaction; `.unverified` never unlocks;
  `.pending` / cancelled / failed / offline all handled with plain-language
  messages, no crashes. No UserDefaults ownership flag anywhere.
- New: `Views/PaywallView.swift` — "Your Free Trial Has Ended", purchase
  button shows the StoreKit localized price, Restore Purchase, back to menu.
- New: `Foldfleet.storekit` — Xcode StoreKit Configuration file for local
  testing (same product ID, $14.99); select it in the scheme on a Mac.
- Integration: `GameViewModel` owns both managers, gates new games / resume /
  rematch / battle start / shots / AI turns on the trial; expiry mid-battle
  cancels a pending AI turn, leaves the battle state intact, and shows the
  paywall. Subtle "Free Trial · 4:32" indicator in Placement and Battle only
  (never on the menu, never after purchase). App refreshes trial + entitlements
  on foreground. No gameplay rules, Duo layout, hinge code or pass-and-play
  flow changed.
- Tests: 13 new XCTest cases (`TrialManagerTests`) — trial start, countdown,
  expiry, relaunch/background persistence, no-reset, `GameAccess` matrix.
  **42 XCTest cases total, 0 failures** on Linux Swift 6.2.1 (was 29).
  Python mirror still 27 passed; harness still 28 passed. No existing test
  weakened or deleted.
- Docs: new `docs/STOREKIT.md` (mechanics, persistence, verification,
  restore, App Store Connect steps, the 22-scenario test checklist);
  release checklist updated (IAP is now a "before submission" item, not a
  "never in v1" item).
- Still unverified: the full iOS build in Xcode 27.1, including all StoreKit
  / SwiftUI code, Duo Simulator purchase testing, and a real iPhone Duo.
  The product does not exist in App Store Connect yet — nothing is live.

## 27 Oct 2026 — Audit + fixes (v1 source, still not Xcode-compiled)

### Compile fixes
- `GameModel.randomFleet(using:)`: unqualified `gridSize` → `GameModel.gridSize` (2 places). This was a confirmed compile error.
- `DuoLayout`: hinge `switch` now has `@unknown default`, in case the SwiftUI hinge-status enum has a `.unknown` case like UIKit's.
- `Persistence` and `SoundEngine` are now `@MainActor` for Swift 6 concurrency; AI task hops back via `MainActor.run`; arpeggio / audio-detach use MainActor tasks.

### Gameplay fixes (all real bugs, tests added, none weakened)
- AI no longer targets around sunk ships (`ShotHistory.sunkShots` / `activeHits`; Hard refuses placements covering a sunk ship).
- Invalid / already-shot taps no longer advance the game (no AI turn, no handoff, no save).
- Pass-and-play BattleView now shows the current shooter's fleets (`ownFleet` / `enemyFleet`) instead of always Player 1's.
- Pass-and-play placement now shows the handoff sheet; battle start hands the phone to Player 1.
- Resume: `GameViewModel.restoreSavedGame(_:)` recomputes shot counts and schedules the AI turn if it is the AI's turn.
- Rematch now starts a fresh match in the same mode and returns to placement.
- Removed the dead Settings ambience/music toggle; EndGameView now shows pass-and-play stats after a pass-and-play match.
- Assets: added missing `AccentColor` colour set; cleaned duplicate AppIcon entries.

### Verification (27 Oct 2026)
- Python mirror `scripts/verify_logic.py`: **27 passed, 0 failed**.
- Linux Swift 6.2.1: typecheck OK (GameModel / AIPlayer / Persistence); harness `scripts/swift_check/run.sh`: **28 passed, 0 failed**; actual XCTest files via SwiftPM: **29 tests, 0 failures**.
- Still unverified: full iOS build in Xcode 27.1, iOS XCTest in Xcode, Duo Simulator, real iPhone Duo.

## 26 Oct 2026 — Initial build (Milestones 1–6)
- Project created: GameModel, AIPlayer, Persistence, SoundEngine, GameViewModel, DuoLayout, OceanGridView, Menu, Placement, Battle, Settings/Help/History, XCTest files, docs, Xcode project.
- Python mirror caught and fixed the game-over shot bug (`fire()` checked phase before game-over).

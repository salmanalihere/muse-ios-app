# Foldfleet — Testing plan (Milestone 7)

## What has been run

- Python rule mirror: `python3 scripts/verify_logic.py` → **27 passed, 0 failed**
  (27 Oct 2026). Covers placement, overlap, edges, hit/miss, repeats, turns,
  sinking, victory, game-over, AI validity, Hard line-extension, AI ignoring
  sunk ships, moving a ship, fire before battle / outside the grid.
- Swift logic harness: `bash scripts/swift_check/run.sh` with Swift 6.2.1 on
  Ubuntu 24.04 → typecheck OK for GameModel / AIPlayer / Persistence, then
  **28 passed, 0 failed** (27 Oct 2026).
- Swift XCTest, actual `FoldfleetTests/` files, run on Linux with Swift 6.2.1
  via SwiftPM (pure-logic target only): **29 tests, 0 failures**
  (20 GameModelTests + 9 AIPlayerTests, 27 Oct 2026).
- Swift XCTest in Xcode / iOS: **not run yet** — needs Xcode 27.1 on a Mac.

## Stage 1 — Unit tests (cloud Mac, first)

```bash
xcodebuild test -scheme Foldfleet -destination 'platform=iOS Simulator,name=iPhone Duo'
```

Expected to pass: `GameModelTests` (14 tests) + `AIPlayerTests` (5 tests).
If a test fails, fix the Swift code — do not delete the test to make it pass.

## Stage 2 — Simulator (Xcode 27.1, Device Hub)

Use Device Hub to open / close / fold / rotate the simulated Duo:

- [ ] Menu, placement, battle, settings, help, history all reachable
- [ ] Inner display, landscape: two grids side by side, no control on the crease
- [ ] Inner display, portrait: layout stays readable
- [ ] Cover display (compact width): single-pane switcher works, nothing clipped
- [ ] Fold mid-battle: game state survives, grids re-lay out, no crash
- [ ] Partially open: layout does not break; hinge callback (if confirmed) widens the gutter
- [ ] Rotate mid-placement: placed ships survive
- [ ] Dynamic Type largest: text does not clip buttons
- [ ] Reduce Motion on: no blocking animation
- [ ] VoiceOver on: every cell announces hit / miss / sunk / water; placement by tapping works

## Stage 3 — Real iPhone Duo (when access is available)

Repeat Stage 2 on hardware. Also check: haptics feel right, sounds are not
too loud, battery / heat over a full match, and the crease gutter in real use.
**Do not claim the game works perfectly on Duo until this stage passes.**

## Stage 4 — Regression

After any change: re-run `verify_logic.py` + the XCTest suite, then re-run
the Stage 2 fold / rotate checks. A layout change is not done until the
fold-mid-battle check passes again.

## Known simulator limits (Xcode 27.1)

StandBy and most app extensions are unavailable in the iPhone Duo Simulator
runtime. Foldfleet does not use those, so this should not block testing.

# Foldfleet — Release checklist (Milestone 8)

Do not submit until every box is checked on a Mac with Xcode 27.1.

## Build

- [ ] `xcodebuild test` passes on iPhone Duo Simulator
- [ ] `DuoLayout.swift` hinge signature confirmed by Xcode autocomplete
- [ ] No warnings treated as errors suppressed; no secrets in source
- [ ] Bundle ID changed from placeholder `com.foldfleet.game` to a permanent ID
- [ ] Version 1.0, build number set; marketing version matches App Store Connect

## App Store assets

- [ ] Final app icon (1024×1024) — the current icon is a generated placeholder
- [ ] iPhone Duo screenshots (inner + outer display, landscape battle + menu)
  — mandatory for submissions from April 2027; submit them now for the Duo badge
- [ ] Screenshots for other required sizes, from the Duo Simulator
- [ ] Honest description: solo + pass-and-play, offline, no account, no ads
- [ ] Privacy labels: Data collected — None (see `docs/PRIVACY.md`)
- [ ] App Review notes: explain the fold layout — two grids, nothing on the
  crease, single-pane fallback on the cover display, landscape recommended
  on the inner display

## Accounts / distribution

- [ ] Apple Developer Program membership active ($99/yr)
- [ ] TestFlight internal test first, then external testers
- [ ] Test on a real iPhone Duo before submitting for review

## Monetization (added 27 Oct 2026, at Salman's explicit request)

The 5-minute trial + one-time unlock is implemented in source
(`docs/STOREKIT.md`). It is **not** live until all of these are done:

- [ ] Non-Consumable `com.foldfleet.fullgame`, $14.99, created in App Store Connect and submitted with a version
- [ ] Paid-app agreement, tax and banking complete
- [ ] Sandbox purchase + restore tested end-to-end (see `docs/STOREKIT.md` checklist)
- [ ] Core game builds and passes tests in Xcode 27.1 first — the trial and
  purchase code is inert until the app itself is verified on a Mac

## Do NOT do before the core game is stable

- [ ] No online multiplayer, no subscriptions in v1
- [ ] No fake multiplayer UI
- [ ] Do not publish without Salman's explicit approval

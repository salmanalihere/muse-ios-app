# Foldfleet — Trial & StoreKit purchase

Free to download, 5 minutes free, then a one-time unlock. StoreKit 2 only.
No Stripe, no PayPal, no external payment system, no fake payment screen.

## Product

| | |
|---|---|
| Product ID | `com.foldfleet.fullgame` |
| Type | Non-Consumable (StoreKit 2) |
| Price | $14.99 (set in App Store Connect; the app shows the StoreKit localized price) |
| What it unlocks | Unlimited Solo + Pass-and-Play, forever, on any device on the same Apple Account |

## Files

- `Foldfleet/Models/TrialManager.swift` — 5-minute trial + `GameAccess` (pure access logic). Foundation + Observation only; typechecked and unit-tested on Linux.
- `Foldfleet/Models/StoreManager.swift` — StoreKit 2: product load, purchase, entitlements, restore, transaction listener. iOS only.
- `Foldfleet/Views/PaywallView.swift` — the unlock screen.
- `Foldfleet.storekit` — Xcode StoreKit Configuration file for local testing (one Non-Consumable, $14.99, `com.foldfleet.fullgame`). **Not** shipped in the app; the scheme points at it for testing only.
- `FoldfleetTests/TrialManagerTests.swift` — 13 tests (trial + `GameAccess`).

## How the 5-minute trial works

- The trial starts **only when gameplay starts**: `GameViewModel.newSoloGame(_:)`,
  `newPassAndPlayGame()` and `restoreSavedGame(_:)` call `trialManager.startTrial()`.
  Opening the app or looking at the menu never starts it.
- Trial length is 300 seconds of **actual elapsed wall-clock time**:
  `remaining = 300 − (now − trialStartDate)`. There is no countdown that can
  be paused — background time counts, force-quit time counts, restart time counts.
- One trial for the whole game. `startTrial()` is a no-op once a start date
  exists, and there is a single `TrialManager` for the app — Solo and
  Pass-and-Play share it, and player handoff never restarts it.
- The ViewModel ticks `trialManager.refresh()` once a second while the app
  lives, and the App calls `refresh()` when the scene becomes active again,
  so the countdown label and expiry are caught promptly after backgrounding.
- While a trial is running, Placement and Battle show a subtle
  `Free Trial · 4:32` indicator (mono, brass). The menu never shows it.
- When the trial expires while the app is open, `TrialManager.onExpired`
  fires once: the ViewModel cancels any pending AI turn (a shot in progress
  is synchronous, so it has already completed — the timer can only fire
  between actions), leaves the battle state exactly as it is, and shows the
  paywall. Further shots, AI turns, battle starts, resumes and rematches are
  all gated until the game is unlocked; unlocking mid-battle lets the same
  battle continue.
- If the trial already expired while the app was closed, no paywall is forced
  on launch. It appears the next time the player tries to start, resume or
  rematch a game.

## How trial persistence works

- One value is persisted: the trial start timestamp, in UserDefaults under
  `foldfleet.trialStartDate` (`SettingsKeys.trialStartDate`).
- Everything else is derived from it (`elapsed = now − start`), so there is
  no timer state to lose on termination or restart, and no way for closing
  the app to reset the trial.
- There is deliberately **no reset API** anywhere in the app.

## How StoreKit entitlement verification works

- On launch, `StoreManager` loads the product (`Product.products(for:)`) and
  re-reads entitlements (`Transaction.currentEntitlements`, which works
  offline from StoreKit's local cache).
- A purchase unlocks **only** on `VerificationResult.verified` for product
  `com.foldfleet.fullgame` with no `revocationDate`. The transaction is then
  finished (`transaction.finish()`) and entitlements are re-read — that
  re-read is what flips `isUnlocked`.
- `.unverified` never unlocks and is never finished. `.pending` (Ask to Buy /
  parental approval) shows a plain-language message and unlocks later via the
  transaction listener. `.userCancelled` returns silently. Network / store
  errors show a plain-language message; the app never crashes over them.
- A transaction listener (`Transaction.updates`) runs from launch, so
  purchases made outside the paywall (App Store, another device, an approved
  Ask to Buy) unlock the game and are finished.
- A refund/revocation removes the unlock on the next entitlement refresh
  (revoked transactions are skipped).
- No UserDefaults flag is ever used as proof of ownership — there is none
  stored. `isUnlocked` is derived from StoreKit entitlements only.
- The purchase button shows `product.displayPrice` (localized, in the
  customer's currency). "$14.99" is only the fallback while the product is
  still loading.

## How Restore Purchase works

- Paywall → "Restore Purchase" → `AppStore.sync()` → re-read entitlements.
  If a verified, non-revoked transaction for `com.foldfleet.fullgame` exists
  on this Apple Account, the game unlocks immediately. It never charges.
- If nothing is found, the paywall says so in plain language.
- Entitlements are also re-checked on every launch and on foreground, so an
  existing owner never sees the trial, the timer, or the paywall.

## App Store Connect — still required (nothing here is live yet)

1. In App Store Connect → Foldfleet → In-App Purchases, create a
   **Non-Consumable** with product ID `com.foldfleet.fullgame`, price $14.99,
   name "Unlock Foldfleet", description "One-time purchase. Play unlimited."
   It must be created with a version submission (Apple requires the first
   non-consumable to be submitted with an app version).
2. The app's paid-app agreement, tax and banking must be complete before the
   product can be sold.
3. In Xcode, select the scheme → Edit Scheme → Run → Options → StoreKit
   Configuration → `Foldfleet.storekit` for local testing. Remove it (or
   leave it — a scheme setting is not shipped) before release; the release
   build talks to the real App Store.
4. Test with a Sandbox Apple ID before submitting; do not use a real purchase
   to test.
5. The `.storekit` file was hand-written to the current Xcode schema
   (version 4.0). If Xcode 27.1 flags anything when you open it, let Xcode's
   editor fix it (or recreate it via File → New → StoreKit Configuration
   File with the same product ID, price and type) — the Swift code only
   depends on the product ID, not on the file.

## StoreKit testing checklist (the 22 scenarios)

Run in Xcode 27.1 with `Foldfleet.storekit` selected in the scheme, on the
iPhone Duo Simulator (Device Hub). "Auto" = covered by XCTest on Linux;
"Manual" = run by hand in the simulator (StoreKit needs the real StoreKit
environment, which does not exist on Linux).

| # | Scenario | How | Status |
|---|---|---|---|
| 1 | New user opens app | Menu appears, no timer, no paywall | Manual |
| 2 | Trial does not start on app launch | Check UserDefaults: no `foldfleet.trialStartDate` after launch | Manual / Auto (`testTrialDoesNotStartOnInit`) |
| 3 | Trial starts when gameplay starts | Tap New Solo Battle → start date set, timer shows in Placement | Manual / Auto (`testStartTrialBeginsCountdown`) |
| 4 | Trial countdown works | Timer ticks down 5:00 → 4:32 (`testFormattedRemaining`) | Manual / Auto |
| 5 | Background app during trial | Background 3 min at 10:02, return at 10:05 → ~2 min left | Manual / Auto (`testBackgroundTimeCounts`) |
| 6 | Reopen app during trial | Force-quit, reopen → timer continues from persisted start | Manual / Auto (`testTrialSurvivesRelaunch`) |
| 7 | Trial reaches 5 minutes | Wait / shorten clock in test → paywall appears, `testTrialExpiresAtFiveMinutes` | Manual / Auto |
| 8 | Paywall appears | "Your Free Trial Has Ended" + Unlock + Restore Purchase | Manual |
| 9 | Purchase succeeds | Buy in the local StoreKit environment → sheet → unlocked at once | Manual |
| 10 | Game unlocks immediately | After purchase, timer gone, new game starts, no paywall | Manual |
| 11 | App closes after purchase | Force-quit | Manual |
| 12 | App reopens after purchase | Still unlocked, no trial, no paywall (entitlements re-read) | Manual |
| 13 | Purchase remains unlocked | As 12, plus after a device restart | Manual |
| 14 | Restore Purchase works | Delete app, reinstall, tap Restore Purchase → unlocked, no charge. Or: Debug → StoreKit → Manage Transactions → refund, then Restore | Manual |
| 15 | Cancelled purchase | Cancel the StoreKit sheet → back on paywall, not unlocked | Manual |
| 16 | Failed purchase | In the .storekit settings enable "Fail Transactions" (or go offline) → plain-language error, no unlock, no crash | Manual |
| 17 | Unverified transaction | Hard to force locally; code path: `.unverified` never unlocks, never finishes, shows a plain-language message. Verify by code review (`StoreManager.purchase()`) | Code review |
| 18 | Solo mode trial | Solo uses the same trial (scenarios 3–7 in Solo) | Manual / Auto |
| 19 | Pass-and-play trial | One shared timer across both players; handoff does not reset it | Manual / Auto (`testStartTrialDoesNotResetAnExistingTrial`) |
| 20 | Switching Solo ↔ Pass-and-Play does not reset trial | Start Solo, quit to menu, start Pass-and-Play → same remaining time | Manual / Auto |
| 21 | Existing purchaser never sees trial | In Transaction Manager, mark the product purchased before launching → menu with no timer, play freely | Manual |
| 22 | Trial state survives app restart | As 6, after a device restart | Manual / Auto |

## Known limitations

- The full iOS app (including `StoreManager`, `GameViewModel`, the views
  and the paywall) has **not** been compiled in Xcode yet — StoreKit and
  SwiftUI do not exist on the Linux machine used for checks. The first
  Xcode 27.1 build is still the gate for everything, monetization included.
- The `.storekit` file's exact schema is Xcode's to confirm on first open
  (see step 5 above).
- The trial is wall-clock based, as specified. A player who changes the
  device clock could affect it; that is the documented behaviour of a
  persisted-timestamp trial and is not worth a server for a $14.99 game.
- The standing instruction "no monetization until the core game is stable"
  was in force when this was built at the user's explicit request. The core
  game logic is verified (see README), but the full Xcode build and Duo
  device testing are still outstanding — get the Xcode build green before
  creating the product in App Store Connect.

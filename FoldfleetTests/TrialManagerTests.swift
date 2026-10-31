import XCTest
@testable import Foldfleet

// TrialManager + GameAccess tests.
//
// These test the pure trial logic with a mock clock and in-memory storage —
// no StoreKit, no runloop, no real time passes. StoreKit purchase flows
// cannot be unit-tested on Linux and are covered by the manual checklist
// in docs/STOREKIT.md (scenarios 9–17, 21) using the .storekit file.

final class TrialManagerTests: XCTestCase {

    private var now: Date!
    private var storage: InMemoryTrialStorage!

    override func setUp() {
        super.setUp()
        now = Date(timeIntervalSince1970: 1_000_000)
        storage = InMemoryTrialStorage()
    }

    private func makeTrial() -> TrialManager {
        TrialManager(storage: storage, now: { [unowned self] in self.now })
    }

    private func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }

    // MARK: Trial does not start on launch

    func testTrialDoesNotStartOnInit() {
        let trial = makeTrial()
        XCTAssertFalse(trial.hasStarted)
        XCTAssertFalse(trial.isExpired)
        XCTAssertFalse(trial.isInTrial)
        XCTAssertEqual(trial.remainingSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(trial.elapsedSeconds, 0, accuracy: 0.001)
    }

    // MARK: Trial starts when gameplay starts

    func testStartTrialBeginsCountdown() {
        let trial = makeTrial()
        trial.startTrial()
        XCTAssertTrue(trial.hasStarted)
        XCTAssertTrue(trial.isInTrial)
        XCTAssertFalse(trial.isExpired)
        XCTAssertEqual(trial.remainingSeconds, 300, accuracy: 0.001)
    }

    // MARK: Elapsed / remaining time

    func testElapsedAndRemainingAfterTwoMinutes() {
        let trial = makeTrial()
        trial.startTrial()
        advance(120)
        trial.refresh()
        XCTAssertEqual(trial.elapsedSeconds, 120, accuracy: 0.001)
        XCTAssertEqual(trial.remainingSeconds, 180, accuracy: 0.001)
        XCTAssertTrue(trial.isInTrial)
    }

    func testFormattedRemaining() {
        let trial = makeTrial()
        trial.startTrial()
        advance(28)  // 272 seconds left
        trial.refresh()
        XCTAssertEqual(trial.formattedRemaining, "4:32")
        XCTAssertEqual(trial.trialLabel, "Free Trial · 4:32")
    }

    // MARK: Expiry

    func testTrialExpiresAtFiveMinutes() {
        let trial = makeTrial()
        trial.startTrial()
        advance(300)
        trial.refresh()
        XCTAssertTrue(trial.isExpired)
        XCTAssertFalse(trial.isInTrial)
        XCTAssertEqual(trial.remainingSeconds, 0, accuracy: 0.001)
    }

    func testOnExpiredCalledExactlyOnce() {
        let trial = makeTrial()
        var calls = 0
        trial.onExpired = { calls += 1 }
        trial.startTrial()
        advance(301)
        trial.refresh()
        trial.refresh()
        trial.refresh()
        XCTAssertEqual(calls, 1)
    }

    // MARK: Persistence — survives relaunch, backgrounding, restart

    func testTrialSurvivesRelaunch() {
        // First "launch": start the trial, use 2 minutes.
        let firstLaunch = makeTrial()
        firstLaunch.startTrial()
        advance(120)
        firstLaunch.refresh()

        // Second "launch": a new manager over the same persisted storage,
        // 10 minutes later in wall-clock time. The trial must NOT reset.
        advance(600)
        let secondLaunch = makeTrial()
        XCTAssertTrue(secondLaunch.hasStarted)
        XCTAssertTrue(secondLaunch.isExpired)
        XCTAssertEqual(secondLaunch.remainingSeconds, 0, accuracy: 0.001)
    }

    func testBackgroundTimeCounts() {
        // Play 2 minutes, then the app is backgrounded for 3 minutes with
        // no refresh() calls in between (no timer runs in the background).
        // On return, only ~0 minutes may remain — the timer never pauses.
        let trial = makeTrial()
        trial.startTrial()
        advance(120)
        trial.refresh()
        XCTAssertEqual(trial.remainingSeconds, 180, accuracy: 0.001)
        advance(180)
        trial.refresh()
        XCTAssertEqual(trial.remainingSeconds, 0, accuracy: 0.001)
        XCTAssertTrue(trial.isExpired)
    }

    func testStartTrialDoesNotResetAnExistingTrial() {
        // Switching modes / handing the phone over / relaunching must not
        // restart the trial. startTrial() is a no-op once started.
        let trial = makeTrial()
        trial.startTrial()
        advance(60)
        trial.refresh()
        trial.startTrial()
        trial.refresh()
        XCTAssertEqual(trial.remainingSeconds, 240, accuracy: 0.001)
        XCTAssertEqual(trial.elapsedSeconds, 60, accuracy: 0.001)
    }

    func testStartTrialAfterExpiryDoesNotReviveIt() {
        let trial = makeTrial()
        trial.startTrial()
        advance(400)
        trial.refresh()
        XCTAssertTrue(trial.isExpired)
        trial.startTrial()
        trial.refresh()
        XCTAssertTrue(trial.isExpired)
        XCTAssertEqual(trial.remainingSeconds, 0, accuracy: 0.001)
    }

    // MARK: GameAccess — the single access rule, all combinations

    func testGameAccessCanStartGame() {
        // Owner: always.
        XCTAssertTrue(GameAccess.canStartGame(isUnlocked: true, trialHasStarted: true, trialExpired: true))
        XCTAssertTrue(GameAccess.canStartGame(isUnlocked: true, trialHasStarted: false, trialExpired: false))
        // Trial not started yet: starting it starts the game.
        XCTAssertTrue(GameAccess.canStartGame(isUnlocked: false, trialHasStarted: false, trialExpired: false))
        // Trial running: can play.
        XCTAssertTrue(GameAccess.canStartGame(isUnlocked: false, trialHasStarted: true, trialExpired: false))
        // Trial expired, not owned: blocked.
        XCTAssertFalse(GameAccess.canStartGame(isUnlocked: false, trialHasStarted: true, trialExpired: true))
    }

    func testGameAccessTrialTimerVisibility() {
        // Only while a trial is actually running.
        XCTAssertTrue(GameAccess.shouldShowTrialTimer(isUnlocked: false, trialHasStarted: true, trialExpired: false))
        XCTAssertFalse(GameAccess.shouldShowTrialTimer(isUnlocked: true, trialHasStarted: true, trialExpired: false))
        XCTAssertFalse(GameAccess.shouldShowTrialTimer(isUnlocked: false, trialHasStarted: false, trialExpired: false))
        XCTAssertFalse(GameAccess.shouldShowTrialTimer(isUnlocked: false, trialHasStarted: true, trialExpired: true))
    }

    func testGameAccessPaywall() {
        XCTAssertTrue(GameAccess.shouldShowPaywall(isUnlocked: false, trialExpired: true))
        XCTAssertFalse(GameAccess.shouldShowPaywall(isUnlocked: true, trialExpired: true))
        XCTAssertFalse(GameAccess.shouldShowPaywall(isUnlocked: false, trialExpired: false))
    }
}

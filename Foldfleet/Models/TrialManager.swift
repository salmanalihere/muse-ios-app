import Foundation
import Observation

// MARK: - Trial storage
//
// The trial start time is the only trial state that must survive the app.
// It is stored as a single persisted timestamp, never as an in-memory
// countdown, so backgrounding, termination, relaunch and device restart
// can never reset or pause the 5-minute trial.
//
// The storage is injected so tests can use an in-memory store and a mock
// clock instead of UserDefaults and wall-clock time. Production uses
// UserDefaults; there is deliberately NO public "reset trial" API —
// nothing in the app may give the player a second free trial.

public protocol TrialStartStorage: AnyObject {
    var trialStartDate: Date? { get set }
}

public final class UserDefaultsTrialStorage: TrialStartStorage {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = SettingsKeys.trialStartDate) {
        self.defaults = defaults
        self.key = key
    }

    public var trialStartDate: Date? {
        get {
            let interval = defaults.double(forKey: key)
            return interval == 0 ? nil : Date(timeIntervalSince1970: interval)
        }
        set {
            if let date = newValue {
                defaults.set(date.timeIntervalSince1970, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

/// In-memory store for tests. Never used in the app.
public final class InMemoryTrialStorage: TrialStartStorage {
    public var trialStartDate: Date?
    public init() {}
}

// MARK: - GameAccess (pure purchase-state logic)
//
// One place that answers "may this player play right now?". The
// ViewModel and the views all go through here, so there is exactly one
// source of truth for access: StoreKit entitlement (isUnlocked) plus the
// trial state. No view invents its own rule.

public enum GameAccess {
    /// May a new game be started? Yes when owned, when the trial has not
    /// started yet (starting it starts the trial), or while it is running.
    /// No only when the trial has expired and the game is not owned.
    public static func canStartGame(isUnlocked: Bool, trialHasStarted: Bool, trialExpired: Bool) -> Bool {
        isUnlocked || !trialHasStarted || !trialExpired
    }

    /// Show the subtle "Free Trial · 4:32" indicator only while a trial is
    /// actually running — never on the menu (gameplay has not started
    /// there), never after purchase, never after expiry.
    public static func shouldShowTrialTimer(isUnlocked: Bool, trialHasStarted: Bool, trialExpired: Bool) -> Bool {
        !isUnlocked && trialHasStarted && !trialExpired
    }

    /// Show the paywall when the trial has expired and the game is not owned.
    public static func shouldShowPaywall(isUnlocked: Bool, trialExpired: Bool) -> Bool {
        !isUnlocked && trialExpired
    }
}

// MARK: - TrialManager
//
// 5-minute free trial, measured as actual elapsed wall-clock time from
// the moment the player first starts a game.
//
//   * Starts only when gameplay starts (GameViewModel calls startTrial()
//     from newSoloGame / newPassAndPlayGame). Opening the app or looking
//     at the menu never starts it.
//   * Elapsed time = now - persisted start date, so time spent in the
//     background, after a force-quit, or after a device restart still
//     counts. The timer is never paused.
//   * One trial per player, shared by Solo and Pass-and-Play: startTrial()
//     is a no-op once a start date exists, and there is a single manager
//     for the whole app — never one per player or per mode.
//   * No timer lives in here: the ViewModel ticks refresh() once a second
//     while the app is alive, and the App calls refresh() when the scene
//     becomes active again (foreground catch-up). Tests call refresh()
//     directly with a mock clock, so no runloop is involved.
//
// This file imports Foundation + Observation only, so it can be
// typechecked and unit-tested on Linux. It knows nothing about StoreKit:
// ownership is StoreManager's job.

@Observable
public final class TrialManager {
    /// The free trial: 5 minutes of gameplay.
    public static let trialDuration: TimeInterval = 5 * 60

    private let storage: TrialStartStorage
    private let duration: TimeInterval
    private let now: () -> Date
    private var expiryNotified = false

    /// Called exactly once, the first time refresh() observes the trial
    /// crossing into expired. Set by GameViewModel; nil in tests.
    public var onExpired: (() -> Void)?

    /// Seconds left in the trial. Updated by refresh(); the UI reads this,
    /// so the countdown label ticks once a second while the ViewModel ticks.
    public private(set) var remainingSeconds: TimeInterval

    public init(
        storage: TrialStartStorage = UserDefaultsTrialStorage(),
        duration: TimeInterval = TrialManager.trialDuration,
        now: @escaping () -> Date = Date.init
    ) {
        self.storage = storage
        self.duration = duration
        self.now = now
        self.remainingSeconds = duration
        refresh()
    }

    // MARK: State

    public var hasStarted: Bool { storage.trialStartDate != nil }

    public var isExpired: Bool { hasStarted && remainingSeconds <= 0 }

    public var isInTrial: Bool { hasStarted && !isExpired }

    public var elapsedSeconds: TimeInterval {
        hasStarted ? max(0, duration - remainingSeconds) : 0
    }

    /// "4:32" — minutes : zero-padded seconds.
    public var formattedRemaining: String {
        let total = max(0, Int(remainingSeconds.rounded()))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// "Free Trial · 4:32" — the subtle in-game indicator.
    public var trialLabel: String { "Free Trial · \(formattedRemaining)" }

    // MARK: Actions

    /// Start the trial at `now()`. A no-op if it already started — the
    /// trial is never restarted, not by switching modes, not by handing
    /// the phone over in pass-and-play, not by relaunching the app.
    public func startTrial() {
        guard storage.trialStartDate == nil else { return }
        storage.trialStartDate = now()
        refresh()
    }

    /// Recompute remaining time from the persisted start date and the
    /// current time. Call once a second while playing, and whenever the
    /// app returns to the foreground, so background time is counted.
    public func refresh() {
        guard let start = storage.trialStartDate else {
            remainingSeconds = duration
            return
        }
        remainingSeconds = max(0, duration - now().timeIntervalSince(start))
        if remainingSeconds <= 0 && !expiryNotified {
            expiryNotified = true
            onExpired?()
        }
    }
}

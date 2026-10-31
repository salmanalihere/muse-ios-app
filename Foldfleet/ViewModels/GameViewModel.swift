import Foundation
import SwiftUI
import UIKit

// MARK: - GameViewModel
//
// Glue between the pure GameState and the views. Owns:
//   * the current match (solo vs AI, or pass-and-play)
//   * placement state, AI turns (with a thinking delay), haptics + sounds
//   * saving / recording the result when a match ends
//
// The ViewModel never invents a rule — every shot goes through GameState.fire().

public enum GameMode: String, Codable, Sendable {
    case solo
    case passAndPlay
}

@MainActor
@Observable
public final class GameViewModel {
    public var state = GameState()
    public var mode: GameMode = .solo
    public var difficulty: Difficulty = .normal
    public var soundEnabled = true
    public var hapticsEnabled = true

    // Placement
    public var selectedShip: ShipType = .carrier
    public var placementOrientation: ShipOrientation = .horizontal
    public var placementFleet = Fleet()
    public var placementPlayer: PlayerID = .playerOne
    /// Pass-and-play: Player 2 has not placed yet.
    public var awaitingSecondPlacement = false

    // Battle UI
    public var message = "Place your fleet to begin."
    public var battleLog: [String] = []
    public var aiThinking = false
    public var showHandoff = false
    public var shotsFiredByPlayerOne = 0
    public var shotsHitByPlayerOne = 0
    public var shotsFiredByPlayerTwo = 0
    public var shotsHitByPlayerTwo = 0

    // MARK: Trial + purchase (one source of truth each)
    //
    // StoreKit entitlement (StoreManager.isUnlocked) decides permanent
    // ownership. TrialManager decides the temporary 5-minute trial. The
    // ViewModel only combines them — it never keeps its own copy of
    // "unlocked". Both managers are shared by Solo and Pass-and-Play, so
    // there is one trial and one entitlement for the whole game.
    public let trialManager = TrialManager()
    public let storeManager = StoreManager()

    /// Present the paywall sheet (driven by RootView).
    public var showPaywall = false

    private var aiTask: Task<Void, Never>?
    /// Ticks trialManager.refresh() once a second while the app lives, so
    /// the countdown label updates and expiry is noticed promptly.
    private var trialTicker: Task<Void, Never>?

    public init() {
        trialManager.onExpired = { [weak self] in
            self?.handleTrialExpired()
        }
        trialTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.trialManager.refresh()
            }
        }
    }

    isolated deinit {
        trialTicker?.cancel()
    }

    /// May a new game be started right now? Owners: always. Everyone
    /// else: only while the trial has not started or is still running.
    public var canStartGame: Bool {
        GameAccess.canStartGame(
            isUnlocked: storeManager.isUnlocked,
            trialHasStarted: trialManager.hasStarted,
            trialExpired: trialManager.isExpired)
    }

    /// Show the subtle "Free Trial · 4:32" indicator (placement + battle
    /// only; never on the menu, never after purchase).
    public var showTrialTimer: Bool {
        GameAccess.shouldShowTrialTimer(
            isUnlocked: storeManager.isUnlocked,
            trialHasStarted: trialManager.hasStarted,
            trialExpired: trialManager.isExpired)
    }

    public var trialLabel: String { trialManager.trialLabel }

    /// The trial has expired and the game is not owned — no further shots
    /// or AI turns until it is unlocked.
    private var trialBlocksPlay: Bool {
        trialManager.isExpired && !storeManager.isUnlocked
    }

    /// Gate for starting (or resuming) a game. Returns true when play is
    /// allowed; otherwise shows the paywall and returns false, leaving
    /// the current state untouched.
    @discardableResult
    public func gateStartGame() -> Bool {
        if canStartGame { return true }
        showPaywall = true
        return false
    }

    /// The trial ran out while the app was open. Finish cleanly: cancel
    /// any pending AI turn (a shot in progress is synchronous, so it has
    /// already completed — the timer can only fire between actions),
    /// leave the battle state exactly as it is, and show the paywall.
    /// The player can unlock and keep playing, or go back to the menu.
    private func handleTrialExpired() {
        guard !storeManager.isUnlocked else { return }
        aiTask?.cancel()
        aiThinking = false
        message = "Your free trial has ended."
        showPaywall = true
    }

    // MARK: Resume

    /// Restore a saved battle. Recomputes shot counts from the fleets
    /// (they are not stored separately), and if it is the AI's turn in a
    /// solo game, schedules the AI — otherwise a resumed AI turn would
    /// wait forever for a tap the player cannot make.
    /// Returns false (and shows the paywall) when the trial has expired
    /// and the game is not owned — a saved battle cannot be resumed
    /// without unlocking.
    @discardableResult
    public func restoreSavedGame(_ saved: SavedGame) -> Bool {
        guard gateStartGame() else { return false }
        trialManager.startTrial()
        aiTask?.cancel()
        aiThinking = false
        state = saved.state
        mode = saved.mode == "passAndPlay" ? .passAndPlay : .solo
        if let d = saved.difficulty { difficulty = d }
        placementFleet = Fleet()
        placementPlayer = .playerOne
        awaitingSecondPlacement = false
        battleLog = []
        shotsFiredByPlayerOne = state.playerTwoFleet.shotsReceived.count
        shotsHitByPlayerOne = state.playerTwoFleet.shotsReceived.values.filter { $0 }.count
        shotsFiredByPlayerTwo = state.playerOneFleet.shotsReceived.count
        shotsHitByPlayerTwo = state.playerOneFleet.shotsReceived.values.filter { $0 }.count
        message = state.isOver
            ? "That battle is over."
            : (state.currentTurn == .playerOne ? "Battle resumed. Your move." : "Battle resumed.")
        if mode == .solo && state.phase == .battle && !state.isOver && state.currentTurn == .playerTwo {
            scheduleAITurn()
        }
        return true
    }

    /// In pass-and-play, "your fleet" is the fleet of whoever is about to
    /// shoot. In solo it is always Player 1. BattleView must use these —
    /// showing playerOneFleet unconditionally leaks Player 1's fleet to
    /// Player 2 and shows Player 2 their own ships as the enemy.
    public var ownFleet: Fleet {
        mode == .passAndPlay && state.currentTurn == .playerTwo ? state.playerTwoFleet : state.playerOneFleet
    }

    public var enemyFleet: Fleet {
        mode == .passAndPlay && state.currentTurn == .playerTwo ? state.playerOneFleet : state.playerTwoFleet
    }

    // MARK: Setup

    /// Starting a game starts the 5-minute trial (unless the game is
    /// already owned). Returns false — and shows the paywall instead —
    /// when the trial has expired and the game is not owned. The same
    /// trial covers Solo and Pass-and-Play: startTrial() is a no-op once
    /// it has started, so switching modes never restarts it.
    @discardableResult
    public func newSoloGame(difficulty: Difficulty) -> Bool {
        guard gateStartGame() else { return false }
        aiTask?.cancel()
        self.mode = .solo
        self.difficulty = difficulty
        self.state = GameState()
        self.placementFleet = Fleet()
        self.placementPlayer = .playerOne
        self.awaitingSecondPlacement = false
        self.battleLog = []
        self.message = "Place your fleet. Tap a cell, then rotate if you need to."
        resetShotCounts()
        trialManager.startTrial()
        return true
    }

    @discardableResult
    public func newPassAndPlayGame() -> Bool {
        guard gateStartGame() else { return false }
        aiTask?.cancel()
        self.mode = .passAndPlay
        self.state = GameState()
        self.placementFleet = Fleet()
        self.placementPlayer = .playerOne
        self.awaitingSecondPlacement = false
        self.battleLog = []
        self.message = "Player 1 — place your fleet. Player 2, look away."
        resetShotCounts()
        trialManager.startTrial()
        return true
    }

    private func resetShotCounts() {
        shotsFiredByPlayerOne = 0; shotsHitByPlayerOne = 0
        shotsFiredByPlayerTwo = 0; shotsHitByPlayerTwo = 0
    }

    // MARK: Placement

    public func placeSelectedShip(at coordinate: Coordinate) -> Bool {
        let ship = Ship(type: selectedShip, origin: coordinate, orientation: placementOrientation)
        guard placementFleet.place(ship) else {
            message = "That spot doesn't fit — try another cell or rotate."
            buzz(.error)
            return false
        }
        SoundEngine.shared.play(.tap, enabled: soundEnabled)
        // Advance to the next unplaced ship, so placement is one tap per ship.
        if let next = ShipType.allCases.first(where: { type in !placementFleet.ships.contains(where: { $0.type == type }) }) {
            selectedShip = next
        }
        message = placementFleet.allShipsPlaced
            ? "Fleet ready. Confirm to begin the battle."
            : "Placed \(ship.type.rawValue). Next: \(selectedShip.rawValue)."
        return true
    }

    public func randomisePlacement() {
        placementFleet = GameState.randomFleet()
        selectedShip = .carrier
        message = "Fleet randomised. Tap a ship in the list, then a cell, to move it."
        SoundEngine.shared.play(.tap, enabled: soundEnabled)
    }

    public func rotatePlacement() {
        placementOrientation = placementOrientation.toggled
        message = "Orientation: \(placementOrientation == .horizontal ? "horizontal" : "vertical")."
    }

    public func confirmPlacement() {
        if mode == .passAndPlay && placementPlayer == .playerOne && !awaitingSecondPlacement {
            // Lock Player 1's fleet in, hand over (privately) to Player 2.
            // showHandoff is honoured by PlacementView (a sheet there),
            // so Player 2's placement does not start on screen until
            // Player 1 has handed the phone over.
            state.setFleet(placementFleet, for: .playerOne)
            placementFleet = Fleet()
            placementPlayer = .playerTwo
            awaitingSecondPlacement = true
            showHandoff = true
            message = "Player 2 — place your fleet. Player 1, look away."
            return
        }
        let player: PlayerID = mode == .passAndPlay ? .playerTwo : .playerOne
        // Starting the battle is starting gameplay: an expired trial
        // blocks it. Placement state is left intact, so the player can
        // unlock and tap "Begin battle" again without re-placing ships.
        // (Player 1's hand-off confirm above is not a battle start, so it
        // is deliberately not gated — the trial started when the game did.)
        guard gateStartGame() else { return }
        state.setFleet(placementFleet, for: player)
        if mode == .solo {
            state.setFleet(GameState.randomFleet(), for: .playerTwo)
        }
        if state.startBattle() {
            awaitingSecondPlacement = false
            message = mode == .solo
                ? "Battle started. Your move — tap the enemy waters."
                : "Battle started. Player 1 fires first."
            SoundEngine.shared.play(.sonar, enabled: soundEnabled)
            // Pass-and-play: Player 2 is holding the phone, Player 1 fires
            // first, so show the handoff sheet in BattleView.
            showHandoff = (mode == .passAndPlay)
            Persistence.shared.saveGame(SavedGame(state: state, mode: mode.rawValue, difficulty: mode == .solo ? difficulty : nil))
        } else {
            message = "Place every ship before starting."
        }
    }

    // MARK: Battle

    /// The human (or current pass-and-play player) fires.
    public func fire(at coordinate: Coordinate) {
        guard state.phase == .battle, !state.isOver else { return }
        // Trial: an expired trial blocks further shots. The battle state
        // is left untouched — unlock and the same battle continues.
        guard !trialBlocksPlay else {
            message = "Your free trial has ended — unlock to keep playing."
            showPaywall = true
            return
        }
        let shooter = state.currentTurn
        // In solo, only Player 1 taps; the AI moves itself.
        if mode == .solo && shooter != .playerOne { return }

        let result = state.fire(at: coordinate, by: shooter)
        handle(result: result, at: coordinate, by: shooter)
        // Only a real shot (hit / miss / sunk) advances the game. An
        // already-shot / invalid tap must NOT hand the phone over, schedule
        // the AI, or save — the same player simply tries another cell.
        switch result {
        case .hit, .miss, .sunk:
            break
        default:
            return
        }
        if state.isOver { finishMatch(); return }

        if mode == .solo {
            scheduleAITurn()
        } else {
            // Pass-and-play: hide the fleets before the other player looks.
            showHandoff = true
        }
        Persistence.shared.saveGame(SavedGame(state: state, mode: mode.rawValue, difficulty: mode == .solo ? difficulty : nil))
    }

    private func handle(result: ShotResult, at coordinate: Coordinate, by shooter: PlayerID) {
        let who = shooter == .playerOne ? "Player 1" : (mode == .solo ? "AI" : "Player 2")
        switch result {
        case .hit(let ship):
            message = "\(who) hit a \(ship.rawValue) at \(coordinate.label)!"
            battleLog.insert("\(who): hit \(ship.rawValue) \(coordinate.label)", at: 0)
            SoundEngine.shared.play(.explosion, enabled: soundEnabled)
            buzz(.success)
            countShot(by: shooter, hit: true)
        case .sunk(let ship):
            message = "\(who) sank the \(ship.rawValue)!"
            battleLog.insert("\(who): SANK \(ship.rawValue) \(coordinate.label)", at: 0)
            SoundEngine.shared.play(.explosion, enabled: soundEnabled)
            buzz(.success)
            countShot(by: shooter, hit: true)
        case .miss:
            message = "\(who) missed at \(coordinate.label)."
            battleLog.insert("\(who): miss \(coordinate.label)", at: 0)
            SoundEngine.shared.play(.splash, enabled: soundEnabled)
            buzz(.light)
            countShot(by: shooter, hit: false)
        case .alreadyShot:
            message = "Already fired there — pick another cell."
            buzz(.error)
        case .notYourTurn:
            message = "Not your turn."
        case .invalid(let why):
            message = why
        case .gameOver:
            message = "The battle is over."
        }
    }

    private func countShot(by shooter: PlayerID, hit: Bool) {
        if shooter == .playerOne {
            shotsFiredByPlayerOne += 1; if hit { shotsHitByPlayerOne += 1 }
        } else {
            shotsFiredByPlayerTwo += 1; if hit { shotsHitByPlayerTwo += 1 }
        }
    }

    private func scheduleAITurn() {
        // Trial: never schedule an AI turn the player is no longer
        // entitled to play. The paywall is already showing (the expiry
        // callback raised it), or appears on the next tap.
        guard !trialBlocksPlay else {
            aiThinking = false
            return
        }
        aiTask?.cancel()
        aiThinking = true
        message = "Admiral is thinking…"
        let delay = difficulty.thinkingDelay
        aiTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            // Hop back to the MainActor ViewModel explicitly.
            await MainActor.run { [weak self] in
                self?.takeAITurn()
            }
        }
    }

    private func takeAITurn() {
        guard state.phase == .battle, !state.isOver, state.currentTurn == .playerTwo else {
            aiThinking = false; return
        }
        // Trial: if it expired while the AI was "thinking", do not fire
        // the shot — show the paywall instead.
        guard !trialBlocksPlay else {
            aiThinking = false
            showPaywall = true
            return
        }
        // Build the AI's legal knowledge ONLY from shots received by
        // Player 1's fleet: which cells were shot, hit or miss, and which
        // ships are sunk. Sunk ships' cells are all cells the AI has
        // already hit (a ship only sinks after every cell is hit), so
        // listing them adds no hidden information — it only stops the AI
        // wasting shots around a ship that is already gone. The AI never
        // sees unhit ship positions.
        let playerOneFleet = state.playerOneFleet
        var history = ShotHistory()
        history.shots = playerOneFleet.shotsReceived
        history.sunkLengths = playerOneFleet.sunkShips.map(\.length)
        history.sunkShots = Set(playerOneFleet.ships.filter(\.isSunk).flatMap(\.cells))
        guard let target = AIPlayer.nextShot(difficulty: difficulty, history: history) else {
            aiThinking = false; return
        }
        aiThinking = false
        let result = state.fire(at: target, by: .playerTwo)
        handle(result: result, at: target, by: .playerTwo)
        if state.isOver { finishMatch(); return }
        message = "Your move — tap the enemy waters."
    }

    // MARK: End of match

    private func finishMatch() {
        aiTask?.cancel()
        aiThinking = false
        Persistence.shared.clearSavedGame()
        let winner = state.winner
        if mode == .solo {
            let won = winner == .playerOne
            message = won ? "Victory! The enemy fleet is destroyed." : "Defeat. Your fleet has fallen."
            SoundEngine.shared.play(won ? .victory : .defeat, enabled: soundEnabled)
            var stats = Persistence.shared.loadStats()
            if won { stats.soloWins += 1 } else { stats.soloLosses += 1 }
            stats.totalShots += shotsFiredByPlayerOne
            stats.totalHits += shotsHitByPlayerOne
            let accuracy = shotsFiredByPlayerOne == 0 ? 0 : Double(shotsHitByPlayerOne) / Double(shotsFiredByPlayerOne)
            stats.bestAccuracyMatch = max(stats.bestAccuracyMatch, accuracy)
            Persistence.shared.saveStats(stats)
            Persistence.shared.recordMatch(MatchRecord(
                mode: "Solo", difficulty: difficulty.rawValue,
                result: won ? "Victory" : "Defeat",
                shotsFired: shotsFiredByPlayerOne, shotsHit: shotsHitByPlayerOne))
        } else {
            let p1Won = winner == .playerOne
            message = p1Won ? "Player 1 wins the battle!" : "Player 2 wins the battle!"
            SoundEngine.shared.play(.victory, enabled: soundEnabled)
            var stats = Persistence.shared.loadStats()
            if p1Won { stats.passAndPlayPlayerOneWins += 1 } else { stats.passAndPlayPlayerTwoWins += 1 }
            stats.totalShots += shotsFiredByPlayerOne + shotsFiredByPlayerTwo
            stats.totalHits += shotsHitByPlayerOne + shotsHitByPlayerTwo
            Persistence.shared.saveStats(stats)
            Persistence.shared.recordMatch(MatchRecord(
                mode: "Pass-and-Play", difficulty: nil,
                result: p1Won ? "Player 1 wins" : "Player 2 wins",
                shotsFired: shotsFiredByPlayerOne + shotsFiredByPlayerTwo,
                shotsHit: shotsHitByPlayerOne + shotsHitByPlayerTwo))
        }
        buzz(.success)
    }

    // MARK: Haptics (respect the setting; iOS also respects system settings)

    private func buzz(_ kind: BuzzKind) {
        guard hapticsEnabled else { return }
        switch kind {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private enum BuzzKind { case light, success, error }
}

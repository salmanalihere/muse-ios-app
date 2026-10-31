import Foundation

// MARK: - Local persistence (offline, no account, no trackers)
//
// Stats + match history are stored as one JSON file in Documents.
// If the file is missing or corrupt, we start fresh — never crash.

public struct MatchRecord: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var mode: String          // "Solo" or "Pass-and-Play"
    public var difficulty: String?   // Solo only
    public var result: String        // "Victory" / "Defeat" / "Player 1 wins" / "Player 2 wins"
    public var shotsFired: Int
    public var shotsHit: Int

    public var accuracy: Double {
        shotsFired == 0 ? 0 : Double(shotsHit) / Double(shotsFired)
    }
}

public struct PlayerStats: Codable, Sendable {
    public var soloWins = 0
    public var soloLosses = 0
    public var passAndPlayPlayerOneWins = 0
    public var passAndPlayPlayerTwoWins = 0
    public var totalShots = 0
    public var totalHits = 0
    public var bestAccuracyMatch: Double = 0   // best single-match accuracy, 0...1

    public var totalMatches: Int { soloWins + soloLosses + passAndPlayPlayerOneWins + passAndPlayPlayerTwoWins }
    public var overallAccuracy: Double { totalShots == 0 ? 0 : Double(totalHits) / Double(totalShots) }
}

public struct SavedGame: Codable, Sendable {
    public var state: GameState
    public var mode: String
    public var difficulty: Difficulty?
    public var savedAt: Date = Date()
}

/// @MainActor: all callers are SwiftUI / the @MainActor ViewModel, and the
/// class holds mutable file state. This keeps Swift 6 concurrency happy
/// without changing any call site.
@MainActor
public final class Persistence {
    public static let shared = Persistence()
    private let fileManager = FileManager.default
    private let historyFile = "foldfleet-history.json"
    private let statsFile = "foldfleet-stats.json"
    private let savedGameFile = "foldfleet-saved-game.json"

    private func url(for file: String) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(file)
    }

    // MARK: History

    public func loadHistory() -> [MatchRecord] {
        load([MatchRecord].self, from: historyFile) ?? []
    }

    public func recordMatch(_ record: MatchRecord) {
        var history = loadHistory()
        history.insert(record, at: 0)
        history = Array(history.prefix(50))  // keep the file small
        save(history, to: historyFile)
    }

    // MARK: Stats

    public func loadStats() -> PlayerStats {
        load(PlayerStats.self, from: statsFile) ?? PlayerStats()
    }

    public func saveStats(_ stats: PlayerStats) {
        save(stats, to: statsFile)
    }

    // MARK: Saved game (one slot — resume where you left off)

    public func saveGame(_ saved: SavedGame) {
        save(saved, to: savedGameFile)
    }

    public func loadSavedGame() -> SavedGame? {
        load(SavedGame.self, from: savedGameFile)
    }

    public func clearSavedGame() {
        try? fileManager.removeItem(at: url(for: savedGameFile))
    }

    public var hasSavedGame: Bool { fileManager.fileExists(atPath: url(for: savedGameFile).path) }

    // MARK: Generic JSON helpers — corrupt data returns nil, never throws to UI

    private func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: file)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to file: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(for: file), options: .atomic)
    }
}

// MARK: - Settings (UserDefaults via @AppStorage in the views)

public enum SettingsKeys {
    public static let soundEnabled = "foldfleet.soundEnabled"
    public static let musicEnabled = "foldfleet.musicEnabled"
    public static let hapticsEnabled = "foldfleet.hapticsEnabled"
    public static let aiThinkingDelay = "foldfleet.aiThinkingDelay"  // multiplier, 0.5...2.0
    public static let reduceMotionOverride = "foldfleet.reduceMotion" // follows system by default
    /// Persisted start of the one 5-minute free trial (seconds since 1970,
    /// 0 = trial never started). TrialManager owns the read/write; the
    /// timestamp — never an in-memory countdown — is what makes the trial
    /// survive backgrounding, termination and relaunch.
    public static let trialStartDate = "foldfleet.trialStartDate"
}

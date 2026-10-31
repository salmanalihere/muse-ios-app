import Foundation

// MARK: - Opponent AI
//
// The AI may ONLY use information legitimately available to it:
//   * which cells it has already shot at, and whether each was a hit or miss
//   * which ships it has sunk (and therefore their lengths)
// It never reads the opponent's fleet. All three levels share that input.

public enum Difficulty: String, CaseIterable, Codable, Sendable {
    case easy = "Easy"
    case normal = "Normal"
    case hard = "Hard"

    public var description: String {
        switch self {
        case .easy: return "Relaxed. Picks any untried cell — good for learning."
        case .normal: return "Hunts, then targets around a hit until the ship sinks."
        case .hard: return "Probability-based targeting. A real challenge — still fair."
        }
    }

    /// Seconds the AI “thinks”, so its move feels human, not instant.
    public var thinkingDelay: TimeInterval {
        switch self { case .easy: return 0.7; case .normal: return 0.9; case .hard: return 1.1 }
    }
}

/// Everything the AI is allowed to know about its own shots so far.
public struct ShotHistory: Sendable {
    public var shots: [Coordinate: Bool] = [:]  // true = hit
    public var sunkLengths: [Int] = []          // lengths of ships already sunk
    /// Coordinates belonging to ships already sunk. Hits here must NOT
    /// attract further targeting — no remaining ship can occupy them.
    public var sunkShots: Set<Coordinate> = []

    public var hits: [Coordinate] { shots.filter(\.value).map(\.key) }
    /// Hits on ships still afloat — the only hits worth targeting around.
    public var activeHits: [Coordinate] { hits.filter { !sunkShots.contains($0) } }
    public var misses: [Coordinate] { shots.filter { !$0.value }.map(\.key) }
    public var tried: Set<Coordinate> { Set(shots.keys) }
    public var untried: [Coordinate] {
        (0..<GameModel.gridSize).flatMap { r in
            (0..<GameModel.gridSize).map { Coordinate(row: r, col: $0) }
        }.filter { !tried.contains($0) }
    }
}

public enum AIPlayer {

    public static func nextShot(
        difficulty: Difficulty,
        history: ShotHistory,
        using rng: inout some RandomNumberGenerator
    ) -> Coordinate? {
        let untried = history.untried
        guard !untried.isEmpty else { return nil }
        switch difficulty {
        case .easy:
            return untried.randomElement(using: &rng)
        case .normal:
            return normalShot(history: history, untried: untried, using: &rng)
        case .hard:
            return hardShot(history: history, untried: untried, using: &rng)
        }
    }

    public static func nextShot(difficulty: Difficulty, history: ShotHistory) -> Coordinate? {
        var rng = SystemRandomNumberGenerator()
        return nextShot(difficulty: difficulty, history: history, using: &rng)
    }

    // MARK: Normal — hunt, then target neighbours of unsunk hits

    private static func normalShot(
        history: ShotHistory,
        untried: [Coordinate],
        using rng: inout some RandomNumberGenerator
    ) -> Coordinate? {
        // Target only around hits on ships still afloat. A sunk ship's
        // hits are in history.sunkShots and must not attract shots.
        let hits = history.activeHits
        guard !hits.isEmpty else {
            // Hunt: checkerboard parity — a 2-cell ship must cover a dark cell.
            let parity = untried.filter { ($0.row + $0.col) % 2 == 0 }
            return (parity.isEmpty ? untried : parity).randomElement(using: &rng)
        }

        var candidates: [Coordinate] = []
        // If two hits are adjacent in a line, extend that line first.
        for hit in hits {
            for neighbour in neighbours(of: hit) where !history.tried.contains(neighbour) {
                candidates.append(neighbour)
            }
        }
        // Prefer a cell that continues a known line of hits.
        let lineExtensions = lineExtensions(from: hits, tried: history.tried)
        if !lineExtensions.isEmpty { return lineExtensions.randomElement(using: &rng) }
        if !candidates.isEmpty { return candidates.randomElement(using: &rng) }
        return untried.randomElement(using: &rng)
    }

    // MARK: Hard — probability density over remaining ship lengths

    private static func hardShot(
        history: ShotHistory,
        untried: [Coordinate],
        using rng: inout some RandomNumberGenerator
    ) -> Coordinate? {
        // Count how many ships of each length are still afloat, using
        // sunkLengths as a multiset.
        var afloatCounts: [Int: Int] = [:]
        for type in ShipType.allCases { afloatCounts[type.length, default: 0] += 1 }
        for length in history.sunkLengths { afloatCounts[length, default: 0] -= 1 }
        let lengths = afloatCounts.flatMap { length, count in Array(repeating: length, count: max(0, count)) }
        guard !lengths.isEmpty else { return untried.randomElement(using: &rng) }

        var score: [Coordinate: Int] = [:]
        for cell in untried { score[cell] = 0 }

        for length in lengths {
            for row in 0..<GameModel.gridSize {
                for col in 0..<GameModel.gridSize {
                    for orientation in [ShipOrientation.horizontal, .vertical] {
                        let cells = (0..<length).map { i in
                            orientation == .horizontal
                                ? Coordinate(row: row, col: col + i)
                                : Coordinate(row: row + i, col: col)
                        }
                        guard cells.allSatisfy(\.isValid) else { continue }
                        // A placement is impossible if it covers a known miss
                        // or a cell of an already-sunk ship.
                        guard !cells.contains(where: { history.shots[$0] == false }) else { continue }
                        guard !cells.contains(where: { history.sunkShots.contains($0) }) else { continue }
                        // Strongly prefer placements covering known unsunk hits.
                        let hitCount = cells.filter { history.activeHits.contains($0) }.count
                        let weight = hitCount == 0 ? 1 : 10 + hitCount * 10
                        for cell in cells where !history.tried.contains(cell) {
                            score[cell, default: 0] += weight
                        }
                    }
                }
            }
        }
        let best = score.values.max() ?? 0
        let bestCells = score.filter { $0.value == best }.map(\.key)
        // Tie-break with parity so the search stays efficient.
        let parityBest = bestCells.filter { ($0.row + $0.col) % 2 == 0 }
        return (parityBest.isEmpty ? bestCells : parityBest).randomElement(using: &rng)
    }

    // MARK: Helpers

    private static func neighbours(of c: Coordinate) -> [Coordinate] {
        [
            Coordinate(row: c.row - 1, col: c.col),
            Coordinate(row: c.row + 1, col: c.col),
            Coordinate(row: c.row, col: c.col - 1),
            Coordinate(row: c.row, col: c.col + 1),
        ].filter(\.isValid)
    }

    /// Cells that extend a straight line of 2+ adjacent hits.
    private static func lineExtensions(from hits: [Coordinate], tried: Set<Coordinate>) -> [Coordinate] {
        var out: [Coordinate] = []
        let hitSet = Set(hits)
        for hit in hits {
            for (dr, dc) in [(0, 1), (1, 0)] {
                let a = Coordinate(row: hit.row - dr, col: hit.col - dc)
                let b = Coordinate(row: hit.row + dr, col: hit.col + dc)
                if hitSet.contains(a) || hitSet.contains(b) {
                    // Extend both ends of the line through this hit.
                    for dir in [-1, 1] {
                        var step = 1
                        while true {
                            let cell = Coordinate(row: hit.row + dr * dir * step, col: hit.col + dc * dir * step)
                            guard cell.isValid, !tried.contains(cell) else { break }
                            if hitSet.contains(cell) { step += 1; continue }
                            out.append(cell)
                            break
                        }
                    }
                }
            }
        }
        return out
    }
}

import XCTest
@testable import Foldfleet

// MARK: - AI tests
//
// The AI must never read the hidden fleet. These tests only give it a
// ShotHistory — the same input the app gives it — and check validity.

final class AIPlayerTests: XCTestCase {

    func testAllDifficultiesReturnValidUntriedCells() {
        for difficulty in Difficulty.allCases {
            var history = ShotHistory()
            for _ in 0..<30 {
                guard let shot = AIPlayer.nextShot(difficulty: difficulty, history: history) else {
                    XCTFail("\(difficulty) returned nil with cells left"); return
                }
                XCTAssertTrue(shot.isValid)
                XCTAssertNil(history.shots[shot], "\(difficulty) repeated a cell")
                history.shots[shot] = false
            }
        }
    }

    func testNormalTargetsAroundAHit() {
        var history = ShotHistory()
        history.shots[Coordinate(row: 5, col: 5)] = true
        var foundAdjacent = false
        for _ in 0..<20 {
            if let shot = AIPlayer.nextShot(difficulty: .normal, history: history) {
                let dist = abs(shot.row - 5) + abs(shot.col - 5)
                if dist == 1 { foundAdjacent = true; break }
            }
        }
        XCTAssertTrue(foundAdjacent, "Normal AI should usually target next to a hit")
    }

    func testHardPrefersCellsNextToHits() {
        var history = ShotHistory()
        history.shots[Coordinate(row: 5, col: 5)] = true
        history.shots[Coordinate(row: 5, col: 6)] = true
        // With two adjacent hits, Hard should extend the line (row 5, col 4 or 7)
        // far more often than chance.
        var lineExtensions = 0
        for _ in 0..<50 {
            if let shot = AIPlayer.nextShot(difficulty: .hard, history: history),
               shot.row == 5 && (shot.col == 4 || shot.col == 7) {
                lineExtensions += 1
            }
        }
        XCTAssertGreaterThan(lineExtensions, 20, "Hard AI should extend a known line of hits")
    }

    func testAINeverShootsAMissCellAgain() {
        var history = ShotHistory()
        history.shots[Coordinate(row: 0, col: 0)] = false
        history.shots[Coordinate(row: 9, col: 9)] = true
        for _ in 0..<50 {
            let shot = AIPlayer.nextShot(difficulty: .hard, history: history)
            XCTAssertNotEqual(shot, Coordinate(row: 0, col: 0))
            XCTAssertNotEqual(shot, Coordinate(row: 9, col: 9))
        }
    }

    func testAIReturnsNilWhenBoardIsExhausted() {
        var history = ShotHistory()
        for r in 0..<10 { for c in 0..<10 { history.shots[Coordinate(row: r, col: c)] = false } }
        XCTAssertNil(AIPlayer.nextShot(difficulty: .hard, history: history))
    }

    // MARK: - Added 27 Oct 2026 (audit: sunk ships must not attract shots)

    func testSunkHitsAreNotActiveHits() {
        var history = ShotHistory()
        history.shots[Coordinate(row: 5, col: 5)] = true
        history.shots[Coordinate(row: 5, col: 6)] = true
        history.shots[Coordinate(row: 2, col: 2)] = true
        history.sunkShots = [Coordinate(row: 5, col: 5), Coordinate(row: 5, col: 6)]
        history.sunkLengths = [2]
        XCTAssertEqual(Set(history.activeHits), [Coordinate(row: 2, col: 2)])
    }

    func testNormalIgnoresSunkShips() {
        // The only hits are on a sunk destroyer. Normal must hunt (parity)
        // instead of targeting around the sunk ship. Adjacent picks should
        // be rare — parity hunting picks ~4 adjacent cells out of ~50.
        var history = ShotHistory()
        history.shots[Coordinate(row: 5, col: 5)] = true
        history.shots[Coordinate(row: 5, col: 6)] = true
        history.sunkShots = [Coordinate(row: 5, col: 5), Coordinate(row: 5, col: 6)]
        history.sunkLengths = [2]
        var adjacent = 0
        for _ in 0..<50 {
            if let shot = AIPlayer.nextShot(difficulty: .normal, history: history),
               (abs(shot.row - 5) + abs(shot.col - 5) == 1) || (abs(shot.row - 5) + abs(shot.col - 6) == 1) {
                adjacent += 1
            }
        }
        XCTAssertLessThan(adjacent, 15, "Normal AI kept targeting a sunk ship (\(adjacent)/50 adjacent)")
    }

    func testHardDoesNotTargetSunkShipCells() {
        // Hard with a sunk ship and one live hit should extend the live
        // hit's line far more often than the sunk ship's line.
        var history = ShotHistory()
        history.shots[Coordinate(row: 5, col: 5)] = true
        history.shots[Coordinate(row: 5, col: 6)] = true
        history.shots[Coordinate(row: 2, col: 2)] = true
        history.shots[Coordinate(row: 2, col: 3)] = true
        history.sunkShots = [Coordinate(row: 5, col: 5), Coordinate(row: 5, col: 6)]
        history.sunkLengths = [2]
        var sunkLine = 0
        var liveLine = 0
        for _ in 0..<50 {
            if let shot = AIPlayer.nextShot(difficulty: .hard, history: history) {
                if shot.row == 5 && (shot.col == 4 || shot.col == 7) { sunkLine += 1 }
                if shot.row == 2 && (shot.col == 1 || shot.col == 4) { liveLine += 1 }
            }
        }
        XCTAssertGreaterThan(liveLine, sunkLine, "Hard AI preferred a sunk ship's line (\(sunkLine)) over a live hit's line (\(liveLine))")
    }

    func testEasyReturnsNilWhenBoardIsExhausted() {
        var history = ShotHistory()
        for r in 0..<10 { for c in 0..<10 { history.shots[Coordinate(row: r, col: c)] = false } }
        history.shots[Coordinate(row: 5, col: 5)] = true
        // Only (5,5) is a hit; every other cell is a miss, so Easy must
        // pick the one untried cell — and never a tried one.
        // (Board is exhausted except that hit, so nextShot must be nil:
        // all cells are tried.)
        XCTAssertNil(AIPlayer.nextShot(difficulty: .easy, history: history))
    }
}

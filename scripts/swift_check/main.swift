// Foldfleet Swift logic harness — runs on Linux with Swift 6.2.1.
// Compiles the REAL GameModel.swift / AIPlayer.swift / Persistence.swift
// from the project and exercises the same cases as the XCTest files.
// This does NOT test SwiftUI / UIKit / AVFoundation files — those need Xcode.
// Run:  swiftc GameModel.swift AIPlayer.swift Persistence.swift main.swift -o foldfleet-check && ./foldfleet-check
import Foundation

var passed = 0, failed = 0
@MainActor func check(_ name: String, _ cond: Bool) {
    if cond { passed += 1; print("  PASS \(name)") } else { failed += 1; print("  FAIL \(name)") }
}
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
}
func placedFleet() -> Fleet {
    var f = Fleet()
    _ = f.place(Ship(type: .carrier, origin: Coordinate(row: 0, col: 0), orientation: .horizontal))
    _ = f.place(Ship(type: .battleship, origin: Coordinate(row: 2, col: 0), orientation: .horizontal))
    _ = f.place(Ship(type: .cruiser, origin: Coordinate(row: 4, col: 0), orientation: .horizontal))
    _ = f.place(Ship(type: .submarine, origin: Coordinate(row: 6, col: 0), orientation: .horizontal))
    _ = f.place(Ship(type: .destroyer, origin: Coordinate(row: 8, col: 0), orientation: .horizontal))
    return f
}
func battleState() -> GameState {
    var s = GameState()
    s.setFleet(placedFleet(), for: .playerOne)
    s.setFleet(GameState.randomFleet(), for: .playerTwo)
    _ = s.startBattle()
    return s
}

print("Placement")
var f = Fleet()
check("valid horizontal", f.place(Ship(type: .carrier, origin: Coordinate(row: 0, col: 0), orientation: .horizontal)))
check("overlap rejected", !f.place(Ship(type: .battleship, origin: Coordinate(row: 0, col: 2), orientation: .horizontal)))
check("off-grid rejected", !f.place(Ship(type: .carrier, origin: Coordinate(row: 0, col: 7), orientation: .horizontal)))
check("edge allowed", f.place(Ship(type: .destroyer, origin: Coordinate(row: 9, col: 8), orientation: .horizontal)))
var rng = SeededRNG(state: 42)
let rf = GameState.randomFleet(using: &rng)
check("seeded random fleet complete", rf.allShipsPlaced && rf.ships.flatMap(\.cells).count == 17)
var allValid = true
for i in 0..<50 { var r = SeededRNG(state: UInt64(i + 1)); let fl = GameState.randomFleet(using: &r); allValid = allValid && fl.allShipsPlaced && Set(fl.ships.flatMap(\.cells)).count == 17 }
check("random fleets valid x50", allValid)

print("Battle")
var g = battleState()
check("cannot start incomplete", { var s = GameState(); s.setFleet(placedFleet(), for: .playerOne); return !s.startBattle() }())
check("out of turn rejected", g.fire(at: Coordinate(row: 0, col: 0), by: .playerTwo) == .notYourTurn)
let enemyCell = g.playerTwoFleet.ships[0].cells[0]
let hitResult = g.fire(at: enemyCell, by: .playerOne)
check("hit detected", hitResult == .hit(ship: g.playerTwoFleet.ships[0].type) || { if case .sunk = hitResult { return true }; return false }())
check("turn switches", g.currentTurn == .playerTwo)
let missCell = (0..<10).flatMap { r in (0..<10).map { Coordinate(row: r, col: $0) } }.first { g.playerOneFleet.ship(at: $0) == nil }!
check("miss detected", g.fire(at: missCell, by: .playerTwo) == .miss)
check("fire before battle invalid", { var s = GameState(); s.setFleet(placedFleet(), for: .playerOne); s.setFleet(placedFleet(), for: .playerTwo); return s.fire(at: Coordinate(row: 0, col: 0), by: .playerOne) == .invalid("Battle has not started.") }())
check("fire outside grid invalid", { var s = battleState(); return s.fire(at: Coordinate(row: 10, col: 0), by: .playerOne) == .invalid("That cell is outside the ocean.") }())

print("Sinking / victory")
var g2 = GameState()
var p1 = Fleet(); _ = p1.place(Ship(type: .destroyer, origin: Coordinate(row: 0, col: 0), orientation: .horizontal))
var p2 = Fleet(); _ = p2.place(Ship(type: .destroyer, origin: Coordinate(row: 5, col: 5), orientation: .horizontal))
g2.playerOneFleet = p1; g2.playerTwoFleet = p2; g2.phase = .battle
check("first hit", g2.fire(at: Coordinate(row: 5, col: 5), by: .playerOne) == .hit(ship: .destroyer))
_ = g2.fire(at: Coordinate(row: 0, col: 0), by: .playerTwo)
check("sunk + victory", g2.fire(at: Coordinate(row: 5, col: 6), by: .playerOne) == .sunk(ship: .destroyer) && g2.isOver && g2.winner == .playerOne)
check("no shots after game over", g2.fire(at: Coordinate(row: 1, col: 1), by: .playerTwo) == .gameOver)

print("Repeat / move")
var g3 = battleState()
_ = g3.fire(at: Coordinate(row: 0, col: 0), by: .playerOne)
_ = g3.fire(at: Coordinate(row: 9, col: 9), by: .playerTwo)
check("alreadyShot, turn unchanged", g3.fire(at: Coordinate(row: 0, col: 0), by: .playerOne) == .alreadyShot && g3.currentTurn == .playerOne)
var fm = Fleet(); _ = fm.place(Ship(type: .carrier, origin: Coordinate(row: 0, col: 0), orientation: .horizontal))
check("moving a ship replaces it", fm.place(Ship(type: .carrier, origin: Coordinate(row: 5, col: 5), orientation: .vertical)) && fm.ships.count == 1)

print("Save / restore")
do {
    var s = battleState()
    _ = s.fire(at: Coordinate(row: 0, col: 0), by: .playerOne)
    let saved = SavedGame(state: s, mode: "solo", difficulty: .normal)
    let data = try JSONEncoder().encode(saved)
    let restored = try JSONDecoder().decode(SavedGame.self, from: data)
    check("round-trip turn + shots + difficulty", restored.state.currentTurn == s.currentTurn && restored.state.playerTwoFleet.shotsReceived.count == s.playerTwoFleet.shotsReceived.count && restored.difficulty == .normal)
    check("corrupt data fails decode", (try? JSONDecoder().decode(SavedGame.self, from: Data("not json".utf8))) == nil)
} catch { check("save/restore threw: \(error)", false) }

print("AI")
for diff in Difficulty.allCases {
    var hist = ShotHistory()
    var ok = true
    for _ in 0..<30 {
        guard let shot = AIPlayer.nextShot(difficulty: diff, history: hist) else { ok = false; break }
        if !shot.isValid || hist.shots[shot] != nil { ok = false; break }
        hist.shots[shot] = false
    }
    check("\(diff.rawValue) valid untried x30", ok)
}
var h = ShotHistory(); h.shots[Coordinate(row: 5, col: 5)] = true; h.shots[Coordinate(row: 5, col: 6)] = true; h.shots[Coordinate(row: 2, col: 2)] = true; h.shots[Coordinate(row: 2, col: 3)] = true
h.sunkShots = [Coordinate(row: 5, col: 5), Coordinate(row: 5, col: 6)]; h.sunkLengths = [2]
check("sunk hits are not active hits", Set(h.activeHits) == [Coordinate(row: 2, col: 2), Coordinate(row: 2, col: 3)])
var adj = 0
for _ in 0..<50 { if let s = AIPlayer.nextShot(difficulty: .normal, history: h), abs(s.row - 5) + abs(s.col - 5) == 1 || abs(s.row - 5) + abs(s.col - 6) == 1 { adj += 1 } }
check("normal ignores sunk ship (\(adj)/50 adjacent)", adj < 15)
var sunkLine = 0, liveLine = 0
for _ in 0..<50 { if let s = AIPlayer.nextShot(difficulty: .hard, history: h) { if s.row == 5 && (s.col == 4 || s.col == 7) { sunkLine += 1 }; if s.row == 2 && (s.col == 1 || s.col == 4) { liveLine += 1 } } }
check("hard prefers live line over sunk (\(liveLine) vs \(sunkLine))", liveLine > sunkLine)
var full = ShotHistory(); for r in 0..<10 { for c in 0..<10 { full.shots[Coordinate(row: r, col: c)] = false } }
check("AI nil when board exhausted", AIPlayer.nextShot(difficulty: .hard, history: full) == nil)
check("labels A1/J10/B4", Coordinate(row: 0, col: 0).label == "A1" && Coordinate(row: 9, col: 9).label == "J10" && Coordinate(row: 3, col: 1).label == "B4")

print("\n\(passed) passed, \(failed) failed")
if failed > 0 { Foundation.exit(1) }

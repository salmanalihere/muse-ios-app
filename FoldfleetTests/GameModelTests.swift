import XCTest
@testable import Foldfleet

// MARK: - Game rules tests
//
// Run on a Mac with:  xcodebuild test -scheme Foldfleet -destination 'platform=iOS Simulator,name=iPhone Duo'
// These tests exercise GameModel only — no UI, no network, no device.

final class GameModelTests: XCTestCase {

    private func placedFleet() -> Fleet {
        var fleet = Fleet()
        XCTAssertTrue(fleet.place(Ship(type: .carrier, origin: Coordinate(row: 0, col: 0), orientation: .horizontal)))
        XCTAssertTrue(fleet.place(Ship(type: .battleship, origin: Coordinate(row: 2, col: 0), orientation: .horizontal)))
        XCTAssertTrue(fleet.place(Ship(type: .cruiser, origin: Coordinate(row: 4, col: 0), orientation: .horizontal)))
        XCTAssertTrue(fleet.place(Ship(type: .submarine, origin: Coordinate(row: 6, col: 0), orientation: .horizontal)))
        XCTAssertTrue(fleet.place(Ship(type: .destroyer, origin: Coordinate(row: 8, col: 0), orientation: .horizontal)))
        return fleet
    }

    private func battleState() -> GameState {
        var state = GameState()
        state.setFleet(placedFleet(), for: .playerOne)
        state.setFleet(GameState.randomFleet(), for: .playerTwo)
        XCTAssertTrue(state.startBattle())
        return state
    }

    func testValidHorizontalAndVerticalPlacement() {
        var fleet = Fleet()
        XCTAssertTrue(fleet.place(Ship(type: .carrier, origin: Coordinate(row: 0, col: 0), orientation: .horizontal)))
        XCTAssertTrue(fleet.place(Ship(type: .destroyer, origin: Coordinate(row: 5, col: 5), orientation: .vertical)))
        XCTAssertEqual(fleet.ships.count, 2)
    }

    func testOverlappingShipsAreRejected() {
        var fleet = Fleet()
        XCTAssertTrue(fleet.place(Ship(type: .carrier, origin: Coordinate(row: 0, col: 0), orientation: .horizontal)))
        XCTAssertFalse(fleet.place(Ship(type: .battleship, origin: Coordinate(row: 0, col: 2), orientation: .horizontal)))
        XCTAssertEqual(fleet.ships.count, 1)
    }

    func testShipsCannotLeaveTheGrid() {
        var fleet = Fleet()
        XCTAssertFalse(fleet.place(Ship(type: .carrier, origin: Coordinate(row: 0, col: 7), orientation: .horizontal)))
        XCTAssertFalse(fleet.place(Ship(type: .carrier, origin: Coordinate(row: 7, col: 0), orientation: .vertical)))
        XCTAssertFalse(fleet.place(Ship(type: .destroyer, origin: Coordinate(row: 10, col: 0), orientation: .horizontal)))
        XCTAssertTrue(fleet.place(Ship(type: .carrier, origin: Coordinate(row: 9, col: 5), orientation: .horizontal)))
        XCTAssertTrue(fleet.place(Ship(type: .destroyer, origin: Coordinate(row: 0, col: 9), orientation: .vertical)))
    }

    func testEdgeOfGridPlacementIsAllowed() {
        var fleet = Fleet()
        XCTAssertTrue(fleet.place(Ship(type: .destroyer, origin: Coordinate(row: 9, col: 8), orientation: .horizontal)))
        XCTAssertTrue(fleet.place(Ship(type: .destroyer, origin: Coordinate(row: 8, col: 9), orientation: .vertical)))
    }

    func testHitAndMiss() {
        var state = battleState()
        // Player 1's opponent fleet is random, so find a known ship cell on
        // Player 2 by inspecting the test fleet directly (tests may do this;
        // the AI in the app never does).
        let enemyShipCell = state.playerTwoFleet.ships[0].cells[0]
        let result = state.fire(at: enemyShipCell, by: .playerOne)
        if case .hit = result { } else if case .sunk = result { } else {
            XCTFail("Expected a hit or sunk, got \(result)")
        }
        // Find a guaranteed miss: a cell with no ship.
        let missCell = (0..<10).flatMap { r in (0..<10).map { Coordinate(row: r, col: $0) } }
            .first { state.playerOneFleet.ship(at: $0) == nil }!
        let miss = state.fire(at: missCell, by: .playerTwo)
        XCTAssertEqual(miss, .miss)
    }

    func testRepeatedAttacksAreRejected() {
        var state = battleState()
        let cell = Coordinate(row: 0, col: 0)
        _ = state.fire(at: cell, by: .playerOne)
        // It is now Player 2's turn; a repeat by Player 1 is out of turn,
        // and a repeat by Player 2 on the same cell against Player 1 is a
        // different target. Test the repeat rule directly on Player 2's fleet:
        var state2 = battleState()
        _ = state2.fire(at: cell, by: .playerOne)
        // Force the turn back in the test by firing Player 2 elsewhere, then
        // Player 1 repeats the first cell.
        _ = state2.fire(at: Coordinate(row: 9, col: 9), by: .playerTwo)
        XCTAssertEqual(state2.fire(at: cell, by: .playerOne), .alreadyShot)
    }

    func testOutOfTurnShotsAreRejected() {
        var state = battleState()
        XCTAssertEqual(state.fire(at: Coordinate(row: 0, col: 0), by: .playerTwo), .notYourTurn)
    }

    func testTurnTransitions() {
        var state = battleState()
        XCTAssertEqual(state.currentTurn, .playerOne)
        _ = state.fire(at: Coordinate(row: 0, col: 0), by: .playerOne)
        XCTAssertEqual(state.currentTurn, .playerTwo)
        _ = state.fire(at: Coordinate(row: 0, col: 0), by: .playerTwo)
        XCTAssertEqual(state.currentTurn, .playerOne)
    }

    func testShipSinkingAndVictory() {
        var state = GameState()
        var p1 = Fleet()
        _ = p1.place(Ship(type: .destroyer, origin: Coordinate(row: 0, col: 0), orientation: .horizontal))
        var p2 = Fleet()
        _ = p2.place(Ship(type: .destroyer, origin: Coordinate(row: 5, col: 5), orientation: .horizontal))
        // Fill the remaining ships off to the side so canStartBattle is true
        // in the real app; here we test sinking directly via the model:
        // use a minimal state by bypassing startBattle's fleet check.
        state.playerOneFleet = p1
        state.playerTwoFleet = p2
        state.phase = .battle
        state.currentTurn = .playerOne
        let first = state.fire(at: Coordinate(row: 5, col: 5), by: .playerOne)
        XCTAssertEqual(first, .hit(ship: .destroyer))
        _ = state.fire(at: Coordinate(row: 0, col: 0), by: .playerTwo)
        let second = state.fire(at: Coordinate(row: 5, col: 6), by: .playerOne)
        XCTAssertEqual(second, .sunk(ship: .destroyer))
        XCTAssertTrue(state.isOver)
        XCTAssertEqual(state.winner, .playerOne)
        XCTAssertEqual(state.fire(at: Coordinate(row: 1, col: 1), by: .playerTwo), .gameOver)
    }

    func testBattleCannotStartWithIncompleteFleet() {
        var state = GameState()
        state.setFleet(placedFleet(), for: .playerOne)
        XCTAssertFalse(state.startBattle())
        XCTAssertEqual(state.phase, .placement)
    }

    func testRandomFleetIsAlwaysValidAndComplete() {
        for _ in 0..<50 {
            let fleet = GameState.randomFleet()
            XCTAssertTrue(fleet.allShipsPlaced)
            let allCells = fleet.ships.flatMap(\.cells)
            XCTAssertEqual(allCells.count, Set(allCells).count, "Random fleet overlapped")
            XCTAssertTrue(allCells.allSatisfy(\.isValid))
        }
    }

    func testSaveAndRestoreRoundTrip() throws {
        var state = battleState()
        _ = state.fire(at: Coordinate(row: 0, col: 0), by: .playerOne)
        let saved = SavedGame(state: state, mode: "solo", difficulty: .normal)
        let data = try JSONEncoder().encode(saved)
        let restored = try JSONDecoder().decode(SavedGame.self, from: data)
        XCTAssertEqual(restored.state.currentTurn, state.currentTurn)
        XCTAssertEqual(restored.state.playerTwoFleet.shotsReceived.count, state.playerTwoFleet.shotsReceived.count)
        XCTAssertEqual(restored.difficulty, .normal)
    }

    func testCorruptSaveDataIsHandledByPersistence() {
        // Persistence.load returns nil for corrupt data instead of throwing.
        // (Covered in the Python mirror too; here we assert the decoder path.)
        let bad = Data("not json".utf8)
        XCTAssertNil(try? JSONDecoder().decode(SavedGame.self, from: bad))
    }

    // MARK: - Added 27 Oct 2026 (audit)

    func testFireBeforeBattleIsInvalidAndDoesNotChangeTurn() {
        var state = GameState()
        state.setFleet(placedFleet(), for: .playerOne)
        state.setFleet(placedFleet(), for: .playerTwo)
        XCTAssertEqual(state.fire(at: Coordinate(row: 0, col: 0), by: .playerOne), .invalid("Battle has not started."))
        XCTAssertEqual(state.currentTurn, .playerOne)
        XCTAssertTrue(state.playerTwoFleet.shotsReceived.isEmpty)
    }

    func testFireOutsideGridIsInvalidAndDoesNotChangeTurn() {
        var state = battleState()
        XCTAssertEqual(state.fire(at: Coordinate(row: 10, col: 0), by: .playerOne), .invalid("That cell is outside the ocean."))
        XCTAssertEqual(state.fire(at: Coordinate(row: -1, col: 5), by: .playerOne), .invalid("That cell is outside the ocean."))
        XCTAssertEqual(state.currentTurn, .playerOne)
    }

    func testAlreadyShotDoesNotChangeTurn() {
        var state = battleState()
        let cell = Coordinate(row: 0, col: 0)
        _ = state.fire(at: cell, by: .playerOne)
        _ = state.fire(at: Coordinate(row: 9, col: 9), by: .playerTwo)
        XCTAssertEqual(state.currentTurn, .playerOne)
        XCTAssertEqual(state.fire(at: cell, by: .playerOne), .alreadyShot)
        XCTAssertEqual(state.currentTurn, .playerOne, "A repeat shot must not hand the turn over")
    }

    func testMovingAShipReplacesItInsteadOfDuplicating() {
        var fleet = Fleet()
        XCTAssertTrue(fleet.place(Ship(type: .carrier, origin: Coordinate(row: 0, col: 0), orientation: .horizontal)))
        XCTAssertTrue(fleet.place(Ship(type: .carrier, origin: Coordinate(row: 5, col: 5), orientation: .vertical)))
        XCTAssertEqual(fleet.ships.count, 1)
        XCTAssertEqual(fleet.ships[0].origin, Coordinate(row: 5, col: 5))
        XCTAssertEqual(fleet.ships[0].orientation, .vertical)
    }

    func testSaveAndRestorePreservesWinnerAndPhase() throws {
        var state = GameState()
        var p1 = Fleet()
        _ = p1.place(Ship(type: .destroyer, origin: Coordinate(row: 0, col: 0), orientation: .horizontal))
        var p2 = Fleet()
        _ = p2.place(Ship(type: .destroyer, origin: Coordinate(row: 5, col: 5), orientation: .horizontal))
        state.playerOneFleet = p1
        state.playerTwoFleet = p2
        state.phase = .battle
        _ = state.fire(at: Coordinate(row: 5, col: 5), by: .playerOne)
        _ = state.fire(at: Coordinate(row: 0, col: 0), by: .playerTwo)
        _ = state.fire(at: Coordinate(row: 5, col: 6), by: .playerOne)
        XCTAssertTrue(state.isOver)
        let data = try JSONEncoder().encode(SavedGame(state: state, mode: "solo", difficulty: .normal))
        let restored = try JSONDecoder().decode(SavedGame.self, from: data)
        XCTAssertEqual(restored.state.winner, .playerOne)
        XCTAssertEqual(restored.state.phase, .finished)
        XCTAssertTrue(restored.state.isOver)
    }

    /// A tiny deterministic RNG, so random-fleet tests are reproducible
    /// instead of relying on SystemRandomNumberGenerator.
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    func testRandomFleetWithSeededRNGIsValidAndComplete() {
        var rng = SeededRNG(state: 42)
        let fleet = GameState.randomFleet(using: &rng)
        XCTAssertTrue(fleet.allShipsPlaced)
        let allCells = fleet.ships.flatMap(\.cells)
        XCTAssertEqual(allCells.count, 17)
        XCTAssertEqual(allCells.count, Set(allCells).count)
        XCTAssertTrue(allCells.allSatisfy(\.isValid))
    }

    func testCoordinateLabels() {
        XCTAssertEqual(Coordinate(row: 0, col: 0).label, "A1")
        XCTAssertEqual(Coordinate(row: 9, col: 9).label, "J10")
        XCTAssertEqual(Coordinate(row: 3, col: 1).label, "B4")
        XCTAssertFalse(Coordinate(row: 10, col: 0).isValid)
    }
}

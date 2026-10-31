import Foundation

// MARK: - Foldfleet game rules
//
// Pure Swift. No SwiftUI, no UIKit, no I/O.
// Every rule in the brief lives here, so the views can never invent a rule
// and the unit tests can exercise the game without launching the app.

/// A cell on the 10×10 ocean. Row and column are 0..<10.
public struct Coordinate: Hashable, Codable, Equatable, Sendable {
    public let row: Int
    public let col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    public var isValid: Bool { (0..<GameModel.gridSize).contains(row) && (0..<GameModel.gridSize).contains(col) }

    /// "B4" style label, for accessibility and the battle log.
    public var label: String {
        guard isValid else { return "(\(row),\(col))" }
        return "\(Character(UnicodeScalar(65 + col)!))\(row + 1)"
    }
}

public enum ShipOrientation: String, Codable, Sendable {
    case horizontal, vertical
    public var toggled: ShipOrientation { self == .horizontal ? .vertical : .horizontal }
}

public enum ShipType: String, CaseIterable, Codable, Sendable {
    case carrier = "Carrier"
    case battleship = "Battleship"
    case cruiser = "Cruiser"
    case submarine = "Submarine"
    case destroyer = "Destroyer"

    public var length: Int {
        switch self {
        case .carrier: return 5
        case .battleship: return 4
        case .cruiser: return 3
        case .submarine: return 3
        case .destroyer: return 2
        }
    }

    /// Short, non-colour identifier used in the UI and VoiceOver.
    public var symbol: String {
        switch self {
        case .carrier: return "C"
        case .battleship: return "B"
        case .cruiser: return "R"
        case .submarine: return "S"
        case .destroyer: return "D"
        }
    }
}

public struct Ship: Codable, Equatable, Sendable {
    public let type: ShipType
    public var origin: Coordinate      // top-most / left-most cell
    public var orientation: ShipOrientation
    public var hits: Set<Coordinate> = []

    public init(type: ShipType, origin: Coordinate, orientation: ShipOrientation) {
        self.type = type
        self.origin = origin
        self.orientation = orientation
    }

    public var cells: [Coordinate] {
        (0..<type.length).map { i in
            orientation == .horizontal
                ? Coordinate(row: origin.row, col: origin.col + i)
                : Coordinate(row: origin.row + i, col: origin.col)
        }
    }

    public var isSunk: Bool { Set(cells).isSubset(of: hits) }
    public var remainingHealth: Int { type.length - hits.count }
}

public enum ShotResult: Equatable, Sendable {
    case hit(ship: ShipType)
    case miss
    case sunk(ship: ShipType)
    case alreadyShot
    case invalid(String)
    case notYourTurn
    case gameOver
}

public enum GamePhase: String, Codable, Sendable {
    case placement
    case battle
    case finished
}

public enum PlayerID: String, Codable, Sendable {
    case playerOne = "Player 1"
    case playerTwo = "Player 2"
    case ai = "Admiral (AI)"

    public var opponent: PlayerID {
        switch self { case .playerOne: return .playerTwo; case .playerTwo: return .playerOne; case .ai: return .playerOne }
    }
}

/// One player's fleet + the record of shots fired *at* them.
public struct Fleet: Codable, Sendable {
    public var ships: [Ship] = []
    /// Cells the opponent has already shot at (hit or miss).
    public var shotsReceived: [Coordinate: Bool] = [:]  // true = hit

    public var allShipsPlaced: Bool { ships.count == ShipType.allCases.count }

    public func ship(at coordinate: Coordinate) -> Ship? {
        ships.first { $0.cells.contains(coordinate) }
    }

    public var sunkShips: [ShipType] { ships.filter(\.isSunk).map(\.type) }
    public var afloatShips: [ShipType] { ships.filter { !$0.isSunk }.map(\.type) }
    public var isDestroyed: Bool { !ships.isEmpty && ships.allSatisfy(\.isSunk) }

    /// Validate a placement: inside the grid, no overlap with other ships.
    public func canPlace(_ ship: Ship, ignoring ignoredType: ShipType? = nil) -> Bool {
        guard ship.cells.allSatisfy(\.isValid) else { return false }
        let others = ships.filter { $0.type != ignoredType }
        return !others.contains { existing in
            !Set(existing.cells).isDisjoint(with: ship.cells)
        }
    }

    public mutating func place(_ ship: Ship) -> Bool {
        guard canPlace(ship, ignoring: ship.type) else { return false }
        ships.removeAll { $0.type == ship.type }
        ships.append(ship)
        return true
    }

    public mutating func remove(_ type: ShipType) {
        ships.removeAll { $0.type == type }
    }
}

public enum GameModel {
    public static let gridSize = 10
    public static let defaultFleet: [ShipType] = ShipType.allCases
}

/// The whole match. One struct, value semantics, Codable so a game can be
/// saved mid-battle and restored exactly.
public struct GameState: Codable, Sendable {
    public var playerOneFleet = Fleet()
    public var playerTwoFleet = Fleet()
    public var currentTurn: PlayerID = .playerOne
    public var phase: GamePhase = .placement
    public var winner: PlayerID?
    public var lastShot: (coordinate: Coordinate, result: ShotResult, by: PlayerID)? = nil

    // LastShot is not Codable (ShotResult carries a Ship). Persist the rest;
    // the log is rebuilt from the fleets on restore. Kept out of Codable by
    // using a custom CodingKeys set below.
    private enum CodingKeys: String, CodingKey {
        case playerOneFleet, playerTwoFleet, currentTurn, phase, winner
    }

    public init() {}

    public var isOver: Bool { phase == .finished }

    public func fleet(for player: PlayerID) -> Fleet {
        player == .playerOne ? playerOneFleet : playerTwoFleet
    }

    public mutating func setFleet(_ fleet: Fleet, for player: PlayerID) {
        if player == .playerOne { playerOneFleet = fleet } else { playerTwoFleet = fleet }
    }

    public var canStartBattle: Bool {
        playerOneFleet.allShipsPlaced && playerTwoFleet.allShipsPlaced
    }

    @discardableResult
    public mutating func startBattle() -> Bool {
        guard phase == .placement, canStartBattle else { return false }
        phase = .battle
        currentTurn = .playerOne
        return true
    }

    /// Fire one shot. Enforces: battle phase, correct turn, valid + fresh cell.
    /// Returns the outcome; the caller (ViewModel) plays sounds / haptics.
    public mutating func fire(at coordinate: Coordinate, by shooter: PlayerID) -> ShotResult {
        guard !isOver else { return .gameOver }
        guard phase == .battle else { return .invalid("Battle has not started.") }
        guard shooter == currentTurn else { return .notYourTurn }
        guard coordinate.isValid else { return .invalid("That cell is outside the ocean.") }

        let target: PlayerID = shooter == .playerOne ? .playerTwo : .playerOne
        var targetFleet = fleet(for: target)
        if targetFleet.shotsReceived[coordinate] != nil { return .alreadyShot }

        let result: ShotResult
        if var ship = targetFleet.ship(at: coordinate) {
            ship.hits.insert(coordinate)
            targetFleet.shotsReceived[coordinate] = true
            // Write the hit back into the fleet's ship list.
            if let idx = targetFleet.ships.firstIndex(where: { $0.type == ship.type }) {
                targetFleet.ships[idx] = ship
            }
            result = ship.isSunk ? .sunk(ship: ship.type) : .hit(ship: ship.type)
        } else {
            targetFleet.shotsReceived[coordinate] = false
            result = .miss
        }
        setFleet(targetFleet, for: target)
        lastShot = (coordinate, result, shooter)

        if targetFleet.isDestroyed {
            phase = .finished
            winner = shooter
        } else {
            currentTurn = target
        }
        return result
    }

    /// Random, valid fleet. Used by “Randomise” and by the AI / pass-and-play
    /// opponent setup. Uses only the public placement rules.
    public static func randomFleet(using rng: inout some RandomNumberGenerator) -> Fleet {
        var fleet = Fleet()
        for type in ShipType.allCases {
            var placed = false
            var attempts = 0
            while !placed && attempts < 500 {
                attempts += 1
                let orientation: ShipOrientation = Bool.random(using: &rng) ? .horizontal : .vertical
                let maxRow = orientation == .horizontal ? GameModel.gridSize - 1 : GameModel.gridSize - type.length
                let maxCol = orientation == .horizontal ? GameModel.gridSize - type.length : GameModel.gridSize - 1
                let ship = Ship(
                    type: type,
                    origin: Coordinate(
                        row: Int.random(in: 0...maxRow, using: &rng),
                        col: Int.random(in: 0...maxCol, using: &rng)),
                    orientation: orientation)
                placed = fleet.place(ship)
            }
        }
        return fleet
    }

    public static func randomFleet() -> Fleet {
        var rng = SystemRandomNumberGenerator()
        return randomFleet(using: &rng)
    }
}

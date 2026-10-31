import SwiftUI

// MARK: - OceanGridView
//
// One reusable 10×10 grid. Used for: own fleet, enemy waters, placement.
// State is NEVER decided here — the caller passes a cell model and a tap handler.
//
// Accessibility: hit / miss / ship / sunk are distinguished by shape AND
// symbol AND label, never by colour alone. Every cell is ≥ 32 pt on a phone,
// larger on the inner display (the grid sizes itself to its container).

public enum CellDisplay: Equatable {
    case water
    case ship(ShipType)          // own ship, unhit — shown only on your own grid
    case hit(ShipType)
    case miss
    case sunk(ShipType)
    case selected
    case previewValid
    case previewInvalid

    public var accessibilityLabel: String {
        switch self {
        case .water: return "Open water"
        case .ship(let t): return "\(t.rawValue), undamaged"
        case .hit(let t): return "Hit on \(t.rawValue)"
        case .miss: return "Miss"
        case .sunk(let t): return "\(t.rawValue) sunk"
        case .selected: return "Selected"
        case .previewValid: return "Valid placement"
        case .previewInvalid: return "Invalid placement"
        }
    }

    /// SF Symbol shown in the cell — the non-colour cue.
    public var symbol: String? {
        switch self {
        case .hit: return "burst.fill"
        case .miss: return "drop.fill"
        case .sunk: return "xmark.octagon.fill"
        case .ship: return "shield.fill"
        case .selected: return "target"
        default: return nil
        }
    }
}

public struct OceanGridView: View {
    public let cells: [[CellDisplay]]  // [row][col]
    public var onTap: ((Coordinate) -> Void)? = nil
    public var isInteractive: Bool = true

    public init(cells: [[CellDisplay]], onTap: ((Coordinate) -> Void)? = nil, isInteractive: Bool = true) {
        self.cells = cells
        self.onTap = onTap
        self.isInteractive = isInteractive
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let cell = side / 10
            VStack(spacing: 0) {
                // Column letters A–J
                HStack(spacing: 0) {
                    Spacer().frame(width: cell * 0.6)
                    ForEach(0..<10, id: \.self) { col in
                        Text(String(Character(UnicodeScalar(65 + col)!)))
                            .font(FleetFonts.mono(11))
                            .foregroundStyle(FleetColors.paper.opacity(0.6))
                            .frame(width: cell, height: cell * 0.6)
                    }
                }
                ForEach(0..<10, id: \.self) { row in
                    HStack(spacing: 0) {
                        Text("\(row + 1)")
                            .font(FleetFonts.mono(11))
                            .foregroundStyle(FleetColors.paper.opacity(0.6))
                            .frame(width: cell * 0.6, height: cell)
                        ForEach(0..<10, id: \.self) { col in
                            cellView(row: row, col: col, size: cell)
                        }
                    }
                }
            }
            .frame(width: side, height: side * 1.06, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .aspectRatio(1.06, contentMode: .fit)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func cellView(row: Int, col: Int, size: CGFloat) -> some View {
        let display = cells[row][col]
        let coord = Coordinate(row: row, col: col)
        Button {
            onTap?(coord)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(background(for: display))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(FleetColors.paper.opacity(0.18), lineWidth: 0.5)
                    )
                if let symbol = display.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(foreground(for: display))
                }
            }
            .frame(width: size - 1, height: size - 1)
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .accessibilityLabel("\(coord.label): \(display.accessibilityLabel)")
        .accessibilityAddTraits(isInteractive ? .isButton : [])
    }

    private func background(for display: CellDisplay) -> Color {
        switch display {
        case .water: return FleetColors.ocean.opacity(0.55)
        case .ship: return FleetColors.ship.opacity(0.85)
        case .hit: return FleetColors.hit.opacity(0.85)
        case .miss: return FleetColors.miss.opacity(0.35)
        case .sunk: return FleetColors.sunk
        case .selected: return FleetColors.brass.opacity(0.7)
        case .previewValid: return Color.green.opacity(0.55)
        case .previewInvalid: return Color.red.opacity(0.55)
        }
    }

    private func foreground(for display: CellDisplay) -> Color {
        switch display {
        case .hit, .sunk: return .white
        case .miss: return FleetColors.paper
        case .ship: return FleetColors.deepOcean
        case .selected: return FleetColors.deepOcean
        default: return FleetColors.paper
        }
    }
}

// MARK: - Helpers: build a cell matrix from a Fleet

public enum GridBuilder {
    /// Your own fleet: ships visible, hits/misses marked.
    public static func ownFleetCells(fleet: Fleet) -> [[CellDisplay]] {
        var grid = Array(repeating: Array(repeating: CellDisplay.water, count: 10), count: 10)
        for ship in fleet.ships {
            for cell in ship.cells {
                grid[cell.row][cell.col] = ship.isSunk ? .sunk(ship.type) : .ship(ship.type)
            }
        }
        for (coord, wasHit) in fleet.shotsReceived {
            if wasHit, let ship = fleet.ship(at: coord) {
                grid[coord.row][coord.col] = ship.isSunk ? .sunk(ship.type) : .hit(ship.type)
            } else if !wasHit {
                grid[coord.row][coord.col] = .miss
            }
        }
        return grid
    }

    /// Enemy waters: only what you have learned — hits, misses, sunk ships.
    /// Never reveals unhit enemy ships.
    public static func enemyCells(fleet: Fleet) -> [[CellDisplay]] {
        var grid = Array(repeating: Array(repeating: CellDisplay.water, count: 10), count: 10)
        for (coord, wasHit) in fleet.shotsReceived {
            if wasHit, let ship = fleet.ship(at: coord) {
                grid[coord.row][coord.col] = ship.isSunk ? .sunk(ship.type) : .hit(ship.type)
            } else if !wasHit {
                grid[coord.row][coord.col] = .miss
            }
        }
        return grid
    }
}

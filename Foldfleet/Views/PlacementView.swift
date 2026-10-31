import SwiftUI

// MARK: - Fleet placement
//
// Tap-to-place is the primary method (accessible, no drag required).
// Tap a ship in the list to select it, tap a cell to place it at that origin.
// Rotate, Randomise and Clear are large buttons. Drag is NOT required.

public struct PlacementView: View {
    @Environment(GameViewModel.self) private var model
    var onBegin: () -> Void
    var onCancel: () -> Void

    public var body: some View {
        DuoLayoutReader { layout in
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if layout.isWide {
                        HStack(alignment: .top, spacing: 32) {
                            gridSection
                            controlsSection
                        }
                        .padding(.horizontal, 24)
                    } else {
                        gridSection
                        controlsSection
                    }
                    Text(model.message)
                        .font(FleetFonts.body(15))
                        .foregroundStyle(FleetColors.brassLight)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .accessibilityLabel("Game status")
                        .accessibilityAddTraits(.updatesFrequently)
                    Spacer(minLength: 24)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: Binding(
            get: { model.showHandoff && model.awaitingSecondPlacement },
            set: { model.showHandoff = $0 }
        )) {
            HandoffView(onReady: { model.showHandoff = false }, targetPlayer: .playerTwo)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(model.mode == .passAndPlay
                 ? (model.placementPlayer == .playerOne ? "Player 1 — Place your fleet" : "Player 2 — Place your fleet")
                 : "Place your fleet")
                .font(FleetFonts.title(28))
                .foregroundStyle(FleetColors.paper)
            // Subtle trial indicator, only while a trial is running.
            // Gameplay has started here, so this is a screen where the
            // timer belongs (it is never shown on the menu).
            if model.showTrialTimer {
                Text(model.trialLabel)
                    .font(FleetFonts.mono(12))
                    .foregroundStyle(FleetColors.brassLight)
                    .accessibilityLabel("Free trial, \(model.trialManager.formattedRemaining) remaining")
            }
            Text("Tap a ship, then tap a cell. Ships cannot overlap or leave the grid.")
                .font(FleetFonts.body(15))
                .foregroundStyle(FleetColors.paper.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
    }

    private var gridSection: some View {
        OceanGridView(cells: placementCells(), onTap: { coord in
            _ = model.placeSelectedShip(at: coord)
        })
        .frame(maxWidth: 520, maxHeight: 520)
    }

    private func placementCells() -> [[CellDisplay]] {
        GridBuilder.ownFleetCells(fleet: model.placementFleet)
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your ships").font(FleetFonts.heading())
            ForEach(ShipType.allCases, id: \.self) { type in
                let placed = model.placementFleet.ships.contains(where: { $0.type == type })
                Button {
                    model.selectedShip = type
                    SoundEngine.shared.play(.tap, enabled: model.soundEnabled)
                } label: {
                    HStack {
                        Text(type.symbol)
                            .font(FleetFonts.mono(14))
                            .frame(width: 28, height: 28)
                            .background(FleetColors.brass.opacity(0.25), in: Circle())
                        VStack(alignment: .leading) {
                            Text(type.rawValue).font(FleetFonts.heading(16))
                            Text("\(type.length) cells" + (placed ? " · placed ✓" : ""))
                                .font(FleetFonts.body(13))
                                .foregroundStyle(FleetColors.paper.opacity(0.7))
                        }
                        Spacer()
                        if model.selectedShip == type && !placed {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(FleetColors.brass)
                        }
                    }
                    .padding(10)
                    .background(model.selectedShip == type ? FleetColors.brass.opacity(0.18) : FleetColors.panel, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(type.rawValue), \(type.length) cells, \(placed ? "placed" : "not placed")")
            }

            HStack(spacing: 10) {
                Button("Rotate (\(model.placementOrientation == .horizontal ? "—" : "|"))") { model.rotatePlacement() }
                    .buttonStyle(GhostButtonStyle())
                Button("Randomise") { model.randomisePlacement() }
                    .buttonStyle(GhostButtonStyle())
            }
            .accessibilityElement(children: .contain)

            Button(model.placementFleet.allShipsPlaced ? "Begin battle" : "Place all ships to begin") {
                model.confirmPlacement()
                if model.state.phase == .battle { onBegin() }
            }
            .buttonStyle(BrassButtonStyle())
            .disabled(!model.placementFleet.allShipsPlaced)
            .accessibilityHint(model.placementFleet.allShipsPlaced ? "Starts the battle" : "Disabled until every ship is placed")

            Button("Cancel") { onCancel() }.buttonStyle(GhostButtonStyle())
        }
        .padding(16)
        .fleetPanel()
    }
}

import SwiftUI

// MARK: - Battle
//
// Wide (inner display, regular width): two zones side by side through
// DuoSplit / ArrangementView, with the fold gutter between them.
// Narrow (cover display / portrait): one zone at a time, switched with a
// segmented control. The rules and the data are identical in both.

public enum BattlePane: String, CaseIterable {
    case fleet = "Your Fleet"
    case target = "Enemy Waters"
}

public struct BattleView: View {
    @Environment(GameViewModel.self) private var model
    var onQuit: () -> Void
    var onRematch: () -> Void = {}

    @State private var pane: BattlePane = .target
    @State private var showEndGame = false

    public var body: some View {
        DuoLayoutReader { layout in
            VStack(spacing: 12) {
                statusBar
                if layout.isWide {
                    DuoSplit {
                        fleetZone(title: "Your Fleet")
                    } secondary: {
                        targetZone(title: "Enemy Waters")
                    }
                    // The gutter: ArrangementView + reservedRegions handle the
                    // fold; we add explicit padding so no control sits on it.
                    .padding(.horizontal, layout.foldGutter)
                } else {
                    Picker("Battle view", selection: $pane) {
                        ForEach(BattlePane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    if pane == .fleet { fleetZone(title: "Your Fleet") } else { targetZone(title: "Enemy Waters") }
                }
                messageBar
                battleLogView
            }
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showEndGame) {
            EndGameView(onRematch: {
                showEndGame = false
                onRematch()
            }, onMenu: {
                showEndGame = false
                onQuit()
            })
        }
        .sheet(isPresented: Binding(
            get: { model.showHandoff },
            set: { model.showHandoff = $0 }
        )) {
            HandoffView(onReady: { model.showHandoff = false })
        }
        .onChange(of: model.state.isOver) { _, isOver in
            if isOver { showEndGame = true }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Quit") { onQuit() }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text(model.mode == .solo ? "Solo · \(model.difficulty.rawValue)" : "Pass-and-Play")
                .font(FleetFonts.mono(13))
            Spacer()
            // Subtle trial indicator, only while a trial is running.
            if model.showTrialTimer {
                Text(model.trialLabel)
                    .font(FleetFonts.mono(12))
                    .foregroundStyle(FleetColors.brassLight)
                    .accessibilityLabel("Free trial, \(model.trialManager.formattedRemaining) remaining")
            }
            if model.aiThinking {
                ProgressView().accessibilityLabel("Opponent is thinking")
            }
            Text(model.state.currentTurn == .playerOne ? "Your turn" : (model.mode == .solo ? "AI turn" : "Player 2 turn"))
                .font(FleetFonts.heading(15))
                .foregroundStyle(FleetColors.brassLight)
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    private func fleetZone(title: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(FleetFonts.heading())
            OceanGridView(
                cells: GridBuilder.ownFleetCells(fleet: model.ownFleet),
                isInteractive: false
            )
            .frame(maxWidth: 520, maxHeight: 520)
            fleetStatus(fleet: model.ownFleet)
        }
        .padding(12)
        .fleetPanel()
    }

    private func targetZone(title: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(FleetFonts.heading())
            OceanGridView(
                cells: GridBuilder.enemyCells(fleet: model.enemyFleet),
                onTap: { coord in model.fire(at: coord) },
                isInteractive: model.state.phase == .battle && !model.state.isOver && !model.aiThinking
            )
            .frame(maxWidth: 520, maxHeight: 520)
            fleetStatus(fleet: model.enemyFleet, enemy: true)
        }
        .padding(12)
        .fleetPanel()
    }

    private func fleetStatus(fleet: Fleet, enemy: Bool = false) -> some View {
        HStack(spacing: 10) {
            ForEach(ShipType.allCases, id: \.self) { type in
                let sunk = fleet.ships.contains(where: { $0.type == type && $0.isSunk })
                Text(type.symbol)
                    .font(FleetFonts.mono(12))
                    .strikethrough(sunk)
                    .foregroundStyle(sunk ? FleetColors.hit : FleetColors.paper.opacity(0.8))
                    .accessibilityLabel("\(type.rawValue) \(sunk ? "sunk" : "afloat")")
            }
            Spacer()
            Text("\(fleet.afloatShips.count) afloat")
                .font(FleetFonts.mono(12))
                .foregroundStyle(FleetColors.paper.opacity(0.7))
        }
    }

    private var messageBar: some View {
        Text(model.message)
            .font(FleetFonts.body(15))
            .foregroundStyle(FleetColors.brassLight)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .accessibilityLabel("Game status")
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var battleLogView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(model.battleLog.prefix(5).enumerated()), id: \.offset) { _, entry in
                    Text(entry)
                        .font(FleetFonts.mono(12))
                        .foregroundStyle(FleetColors.paper.opacity(0.75))
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 20)
    }
}

// MARK: - Handoff (pass-and-play privacy)

public struct HandoffView: View {
    var onReady: () -> Void
    /// Who the phone is being handed to. Defaults to whoever's turn it is
    /// in battle; placement hands over to Player 2 explicitly.
    var targetPlayer: PlayerID? = nil
    @Environment(GameViewModel.self) private var model

    public var body: some View {
        let target = targetPlayer ?? model.state.currentTurn
        return VStack(spacing: 20) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(FleetColors.brass)
            Text("Pass the phone")
                .font(FleetFonts.title(28))
            Text(target == .playerOne
                 ? "Hand the Duo to Player 1. Player 2 — look away."
                 : "Hand the Duo to Player 2. Player 1 — look away.")
                .font(FleetFonts.body())
                .multilineTextAlignment(.center)
                .foregroundStyle(FleetColors.paper.opacity(0.8))
            Text("Fleets are hidden until you tap Ready.")
                .font(FleetFonts.body(14))
                .foregroundStyle(FleetColors.brassLight)
            Button("I'm ready — show my fleet") { onReady() }
                .buttonStyle(BrassButtonStyle())
        }
        .padding(28)
        .oceanBackground()
        .interactiveDismissDisabled(true)
        .accessibilityLabel("Pass the phone. Fleets are hidden.")
    }
}

// MARK: - End of match

public struct EndGameView: View {
    var onRematch: () -> Void
    var onMenu: () -> Void
    @Environment(GameViewModel.self) private var model

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: model.state.winner == .playerOne ? "trophy.fill" : "flag.slash.fill")
                .font(.system(size: 56))
                .foregroundStyle(FleetColors.brass)
            Text(model.message)
                .font(FleetFonts.title(28))
                .multilineTextAlignment(.center)
            let stats = Persistence.shared.loadStats()
            Text(model.mode == .passAndPlay
                 ? "Player 1 wins: \(stats.passAndPlayPlayerOneWins) · Player 2 wins: \(stats.passAndPlayPlayerTwoWins) · Matches: \(stats.totalMatches)"
                 : "Solo wins: \(stats.soloWins) · Losses: \(stats.soloLosses) · Matches: \(stats.totalMatches)")
                .font(FleetFonts.body(15))
                .foregroundStyle(FleetColors.paper.opacity(0.8))
            Button("Rematch") { onRematch() }.buttonStyle(BrassButtonStyle())
            Button("Main menu") { onMenu() }.buttonStyle(GhostButtonStyle())
        }
        .padding(28)
        .oceanBackground()
        .interactiveDismissDisabled(true)
    }
}

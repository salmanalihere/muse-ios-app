import SwiftUI

// MARK: - App entry

@main
struct FoldfleetApp: App {
    @State private var model = GameViewModel()
    @AppStorage(SettingsKeys.soundEnabled) private var soundEnabled = true
    @AppStorage(SettingsKeys.hapticsEnabled) private var hapticsEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .onAppear {
                    model.soundEnabled = soundEnabled
                    model.hapticsEnabled = hapticsEnabled
                }
                .onChange(of: scenePhase) { _, phase in
                    // Foreground catch-up: the trial is elapsed wall-clock
                    // time, so a return from the background must recompute
                    // it immediately (not wait for the next 1-second tick),
                    // and entitlements are re-checked (e.g. a purchase made
                    // on another device, or a refund, while this app slept).
                    if phase == .active {
                        model.trialManager.refresh()
                        Task { await model.storeManager.refreshEntitlements() }
                    }
                }
        }
    }
}

public enum AppScreen: Hashable {
    case menu
    case placement
    case battle
    case settings
    case help
    case history
}

public struct RootView: View {
    @Environment(GameViewModel.self) private var model
    @State private var screen: AppScreen = .menu

    public var body: some View {
        NavigationStack {
            ZStack {
                switch screen {
                case .menu:
                    MenuView(
                        onSolo: { difficulty in
                            // newSoloGame returns false (and shows the
                            // paywall) when the trial has expired and the
                            // game is not owned — stay on the menu then.
                            if model.newSoloGame(difficulty: difficulty) {
                                screen = .placement
                            }
                        },
                        onPassAndPlay: {
                            if model.newPassAndPlayGame() {
                                screen = .placement
                            }
                        },
                        onSettings: { screen = .settings },
                        onHelp: { screen = .help },
                        onHistory: { screen = .history },
                        onResume: {
                            if let saved = Persistence.shared.loadSavedGame() {
                                if model.restoreSavedGame(saved) {
                                    screen = .battle
                                }
                            }
                        },
                        hasSavedGame: Persistence.shared.hasSavedGame
                    )
                case .placement:
                    PlacementView(onBegin: { screen = .battle }, onCancel: { screen = .menu })
                case .battle:
                    BattleView(onQuit: { screen = .menu }, onRematch: {
                        // Rematch starts a fresh match in the SAME mode and
                        // returns to placement — staying on the battle screen
                        // with empty fleets was a bug in v1. An expired
                        // trial blocks the rematch and shows the paywall.
                        let started: Bool
                        if model.mode == .passAndPlay {
                            started = model.newPassAndPlayGame()
                        } else {
                            started = model.newSoloGame(difficulty: model.difficulty)
                        }
                        if started { screen = .placement }
                    })
                case .settings:
                    SettingsView(onDone: { screen = .menu })
                case .help:
                    HelpView(onDone: { screen = .menu })
                case .history:
                    HistoryView(onDone: { screen = .menu })
                }
            }
            .oceanBackground()
        }
        // The paywall is presented from the root, so it can appear from
        // any screen (menu, placement, battle). Closing it without buying
        // always returns to the menu — never back into a game the player
        // is no longer entitled to play.
        .sheet(isPresented: Binding(
            get: { model.showPaywall },
            set: { model.showPaywall = $0 }
        )) {
            PaywallView(onClose: {
                model.showPaywall = false
                screen = .menu
            })
        }
        .onChange(of: model.storeManager.isUnlocked) { _, unlocked in
            // A verified purchase dismisses the paywall immediately,
            // wherever it was shown from.
            if unlocked { model.showPaywall = false }
        }
    }
}

// MARK: - Main menu

public struct MenuView: View {
    var onSolo: (Difficulty) -> Void
    var onPassAndPlay: () -> Void
    var onSettings: () -> Void
    var onHelp: () -> Void
    var onHistory: () -> Void
    var onResume: () -> Void
    var hasSavedGame: Bool

    @State private var difficulty: Difficulty = .normal
    @State private var showDifficulty = false

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "sailboat.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(FleetColors.brass)
                        .accessibilityHidden(true)
                    Text("FOLDFLEET")
                        .font(FleetFonts.title(40))
                        .foregroundStyle(FleetColors.paper)
                    Text("A naval strategy game for iPhone Duo")
                        .font(FleetFonts.body())
                        .foregroundStyle(FleetColors.paper.opacity(0.75))
                        .multilineTextAlignment(.center)
                    Text("Open the Duo flat. Your fleet on the left,\nthe enemy waters on the right.")
                        .font(FleetFonts.body(15))
                        .foregroundStyle(FleetColors.brassLight)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                VStack(spacing: 12) {
                    if hasSavedGame {
                        Button("Resume saved battle") { onResume() }
                            .buttonStyle(BrassButtonStyle())
                    }
                    Button("New Solo Battle") { showDifficulty = true }
                        .buttonStyle(BrassButtonStyle())
                    Button("Pass-and-Play (2 players, one phone)") { onPassAndPlay() }
                        .buttonStyle(GhostButtonStyle())
                }

                // Difficulty picker — shown inline, not hidden behind a sheet.
                if showDifficulty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Difficulty").font(FleetFonts.heading())
                        ForEach(Difficulty.allCases, id: \.self) { level in
                            Button {
                                difficulty = level
                                onSolo(level)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(level.rawValue).font(FleetFonts.heading(17))
                                    Text(level.description).font(FleetFonts.body(14))
                                        .foregroundStyle(FleetColors.paper.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(difficulty == level ? FleetColors.brass.opacity(0.25) : FleetColors.panel, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(level.rawValue). \(level.description)")
                        }
                    }
                    .fleetPanel()
                    .padding()
                }

                HStack(spacing: 16) {
                    Button("Settings") { onSettings() }.buttonStyle(GhostButtonStyle())
                    Button("How to play") { onHelp() }.buttonStyle(GhostButtonStyle())
                    Button("History") { onHistory() }.buttonStyle(GhostButtonStyle())
                }

                StatsSummaryView()
                Text("Offline · No account · No ads")
                    .font(FleetFonts.mono(12))
                    .foregroundStyle(FleetColors.paper.opacity(0.5))
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .accessibilityLabel("Foldfleet main menu")
    }
}

public struct StatsSummaryView: View {
    public var body: some View {
        let stats = Persistence.shared.loadStats()
        return HStack(spacing: 24) {
            stat("Wins", "\(stats.soloWins)")
            stat("Losses", "\(stats.soloLosses)")
            stat("Matches", "\(stats.totalMatches)")
            stat("Accuracy", stats.totalShots == 0 ? "—" : "\(Int(stats.overallAccuracy * 100))%")
        }
        .fleetPanel()
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Solo wins \(stats.soloWins), losses \(stats.soloLosses), \(stats.totalMatches) matches played")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(FleetFonts.heading(20)).foregroundStyle(FleetColors.brassLight)
            Text(label).font(FleetFonts.mono(11)).foregroundStyle(FleetColors.paper.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
    }
}

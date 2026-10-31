import SwiftUI

// MARK: - Settings, Help, History

public struct SettingsView: View {
    var onDone: () -> Void
    @AppStorage(SettingsKeys.soundEnabled) private var soundEnabled = true
    @AppStorage(SettingsKeys.hapticsEnabled) private var hapticsEnabled = true
    @Environment(GameViewModel.self) private var model

    public var body: some View {
        Form {
            Section("Sound") {
                Toggle("Sound effects", isOn: $soundEnabled)
                Button("Play sonar test") {
                    SoundEngine.shared.play(.sonar, enabled: soundEnabled)
                }
                // No ambience/music toggle in v1: there is no looping
                // ambience track. A previous toggle did nothing, so it
                // was removed rather than left as a dead control.
                Text("Sounds are synthesised in the app. No music track in v1.")
                    .font(.footnote)
            }
            Section("Touch") {
                Toggle("Haptics (vibration)", isOn: $hapticsEnabled)
                Text("Haptics also follow your system settings. Turn them off here if you prefer a quiet game.")
                    .font(.footnote)
            }
            Section("About") {
                LabeledContent("Version", value: "1.0 (1)")
                LabeledContent("Designed for", value: "iPhone Duo · iOS 27.1")
                LabeledContent("Data", value: "Stored only on this phone")
            }
            Section {
                Button("Done") { onDone() }.buttonStyle(BrassButtonStyle())
            }
        }
        .navigationTitle("Settings")
        .onChange(of: soundEnabled) { _, v in model.soundEnabled = v }
        .onChange(of: hapticsEnabled) { _, v in model.hapticsEnabled = v }
    }
}

public struct HelpView: View {
    var onDone: () -> Void

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How to play").font(FleetFonts.title(28))
                helpSection("The goal", "Sink all five enemy ships before yours are sunk. Carrier (5), Battleship (4), Cruiser (3), Submarine (3), Destroyer (2).")
                helpSection("Placing ships", "Tap a ship, then tap a cell. Use Rotate to turn it, Randomise to shuffle the fleet. Ships cannot overlap or leave the grid. You can move a ship by tapping it again and placing it elsewhere before you confirm.")
                helpSection("Firing", "On your turn, tap a cell in Enemy Waters. A burst means a hit, a drop means a miss, a red octagon means that ship is sunk. You get one shot per turn.")
                helpSection("iPhone Duo", "Open the Duo flat for the best view: your fleet on the left, enemy waters on the right. Nothing important sits on the fold. On the cover display, or in portrait, switch between Your Fleet and Enemy Waters with the switcher at the top. Landscape is recommended on the inner display, but portrait works.")
                helpSection("Pass-and-Play", "Two players, one phone, no internet. After each turn the phone shows a handoff screen — fleets stay hidden until the next player taps Ready.")
                helpSection("Accessibility", "Every cell announces its state by VoiceOver (hit, miss, sunk, open water) with a shape and a symbol, not colour alone. Placement works entirely by tapping — drag is never required. The game respects Reduce Motion and Dynamic Type.")
                Button("Done") { onDone() }.buttonStyle(BrassButtonStyle())
            }
            .padding(20)
        }
        .navigationTitle("How to play")
    }

    private func helpSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(FleetFonts.heading())
            Text(body).font(FleetFonts.body()).foregroundStyle(FleetColors.paper.opacity(0.85))
        }
    }
}

public struct HistoryView: View {
    var onDone: () -> Void
    @State private var history: [MatchRecord] = []

    public var body: some View {
        VStack {
            if history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 44)).foregroundStyle(FleetColors.brass)
                    Text("No matches yet").font(FleetFonts.heading())
                    Text("Finish a battle and it will appear here.").font(FleetFonts.body()).foregroundStyle(FleetColors.paper.opacity(0.75))
                }
                .padding()
            } else {
                List(history) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.result).font(FleetFonts.heading(16))
                        Text("\(record.mode)\(record.difficulty.map { " · \($0)" } ?? "") · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(FleetFonts.body(13)).foregroundStyle(FleetColors.paper.opacity(0.7))
                        Text("Shots \(record.shotsFired) · Hits \(record.shotsHit) · Accuracy \(Int(record.accuracy * 100))%")
                            .font(FleetFonts.mono(12)).foregroundStyle(FleetColors.paper.opacity(0.7))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            Button("Done") { onDone() }.buttonStyle(BrassButtonStyle()).padding()
        }
        .navigationTitle("Match history")
        .onAppear { history = Persistence.shared.loadHistory() }
    }
}

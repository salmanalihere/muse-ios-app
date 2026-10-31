import SwiftUI

// MARK: - DuoLayout — the ONE file that knows about the fold
//
// Everything else in the app asks this file one question:
//   "Do I have room for two grids side by side?"
// and gets a plain answer. That keeps a future Xcode API change to one file.
//
// API status, re-checked 27 Oct 2026 against Apple Tech Talk 111464
// ("Leverage multiple displays and scenes on iPhone Duo",
// developer.apple.com/videos/play/tech-talks/111464/) and the iOS 27.1 SDK
// material summarised from it:
//
// CONFIRMED (Apple Tech Talk, official):
//   * `.onHingeChange { _, context in ... }` — closure takes the previous
//     and the current hinge context. `context.hinge` is nil on a device
//     with no hinge. `hinge.status` is `.closed` / `.partiallyOpen` /
//     `.fullyOpen`, and `hinge.angle` is a continuous Angle (`.degrees`).
//     Apple: hinge is for interactions/effects, NOT for layout.
//   * `ArrangementView { primary } secondary: { secondary }` with
//     `.arrangementViewStyle(.split.axes(.horizontal))` — iOS 27.1.
//     Do not put a NavigationSplitView inside one, and do not put one
//     inside a List / ScrollView.
//   * `GeometryProxy.reservedRegions(kind: .division, options:
//     .includeInactive)` / `UIView.reservedRegions(...)` — `.division` is
//     the fold, `.occlusion` is the camera. A division region is active
//     only when folded and zero width when flat.
//
// NOT YET CONFIRMED in Apple's published API reference (as of 27 Oct 2026):
//   * A dedicated developer.apple.com/documentation page for
//     `onHingeChange` / `UIHingeInteraction` / `ArrangementView` was not
//     found by search — the Tech Talk is the authoritative source so far.
//     Final check on the cloud Mac: let Xcode 27.1 autocomplete confirm
//     these three calls in this file. If a signature differs, fix it here.
//   * Whether the SwiftUI hinge-status enum also has a `.unknown` case
//     (the UIKit `UIHinge` enum is reported to include one). This file
//     handles it with `@unknown default`, so either way it compiles.
//   * The exact `reservedRegions` overload spelling (`.includeInactive`
//     as a single option vs. `[.includeInactive]`). Both spellings appear
//     in Apple-derived examples; Xcode autocomplete is the final check.
//
// Layout rule (Apple guidance): branch on size class + available geometry,
// never on a device name or a fixed pixel width. The hinge callback below
// only records state for information — layout never depends on it, so the
// game is fully playable on an ordinary iPhone / the cover display with
// no hinge at all.

public enum HingeStatus: Equatable, Sendable {
    case noHinge
    case closed
    case partiallyOpen
    case fullyOpen
}

/// What the rest of the app needs to know about the current display.
public struct DuoLayoutInfo: Equatable {
    public var isWide: Bool          // regular width — room for two grids
    public var hinge: HingeStatus = .noHinge
    public var hingeAngleDegrees: Double? = nil
    /// The fold's rectangle in this view's coordinates, if known (even when inactive).
    public var divisionFrame: CGRect? = nil
    /// Half-width of the gutter to keep clear around the fold.
    public var foldGutter: CGFloat { 24 }

    public var isDuoInnerDisplay: Bool { isWide && hinge != .noHinge }
}

public struct DuoLayoutReader<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var hinge: HingeStatus = .noHinge
    @State private var hingeAngle: Double? = nil
    private let content: (DuoLayoutInfo) -> Content

    public init(@ViewBuilder content: @escaping (DuoLayoutInfo) -> Content) {
        self.content = content
    }

    public var body: some View {
        GeometryReader { proxy in
            let division = proxy.reservedRegions(kind: .division, options: .includeInactive)
            let info = DuoLayoutInfo(
                isWide: horizontalSizeClass == .regular && proxy.size.width >= 620,
                hinge: hinge,
                hingeAngleDegrees: hingeAngle,
                divisionFrame: division.first?.frame
            )
            content(info)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Hinge observation — Apple Tech Talk 111464: the closure receives
        // (previousContext, currentContext); a nil hinge means no hinge.
        // Hinge state is recorded for information only; layout uses size
        // class + ArrangementView + reserved regions, never the angle.
        .onHingeChange { _, context in
            if let hingeValue = context.hinge {
                switch hingeValue.status {
                case .closed: hinge = .closed
                case .partiallyOpen: hinge = .partiallyOpen
                case .fullyOpen: hinge = .fullyOpen
                default: hinge = .noHinge
                }
                hingeAngle = hingeValue.angle.degrees
            } else {
                hinge = .noHinge
                hingeAngle = nil
            }
        }
    }
}

/// Two-zone battle layout.
/// Wide (inner display): left + right with a clear fold gutter between them.
/// Narrow (cover display / portrait phone): the two zones stack, and the
/// caller shows a Fleet / Target switcher instead — see BattleView.
public struct DuoSplit<Primary: View, Secondary: View>: View {
    private let primary: Primary
    private let secondary: Secondary

    public init(@ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
        self.primary = primary()
        self.secondary = secondary()
    }

    public var body: some View {
        // ArrangementView is the iOS 27.1 system container for exactly this:
        // two views, split along the fold when there is room.
        ArrangementView {
            primary
        } secondary: {
            secondary
        }
        .arrangementViewStyle(.split.axes(.horizontal))
    }
}

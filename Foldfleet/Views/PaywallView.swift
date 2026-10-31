import SwiftUI

// MARK: - Paywall
//
// Foldfleet-themed unlock screen. Shown when the 5-minute free trial has
// expired and the game is not owned, or when the player taps a locked
// action. The price on the purchase button always comes from the StoreKit
// Product (localized, customer's currency); "$14.99" appears only as the
// fallback while the product is still loading.
//
// The purchase itself is Apple's StoreKit sheet — there is no fake
// payment screen anywhere in the app. Dismissal is only through the
// explicit "Back to menu" button, so the paywall cannot be swiped away
// to sneak back into a locked game.

public struct PaywallView: View {
    @Environment(GameViewModel.self) private var model
    var onClose: () -> Void

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "sailboat.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(FleetColors.brass)
                    .padding(.top, 24)
                    .accessibilityHidden(true)

                Text("Your Free Trial Has Ended")
                    .font(FleetFonts.title(28))
                    .foregroundStyle(FleetColors.paper)
                    .multilineTextAlignment(.center)

                Text("Unlock the full game to continue playing Foldfleet.")
                    .font(FleetFonts.body())
                    .foregroundStyle(FleetColors.paper.opacity(0.8))
                    .multilineTextAlignment(.center)

                VStack(spacing: 6) {
                    Text("Unlock Foldfleet — $14.99")
                        .font(FleetFonts.heading(20))
                        .foregroundStyle(FleetColors.brassLight)
                    Text("One-time purchase. Play unlimited.")
                        .font(FleetFonts.body(15))
                        .foregroundStyle(FleetColors.paper.opacity(0.8))
                    Text("Unlimited Solo and Pass-and-Play battles, on this Duo and any other device signed in to the same Apple Account.")
                        .font(FleetFonts.body(14))
                        .foregroundStyle(FleetColors.paper.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .fleetPanel()

                VStack(spacing: 12) {
                    Button {
                        Task { await model.storeManager.purchase() }
                    } label: {
                        if model.storeManager.isPurchasing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(FleetColors.paper)
                        } else {
                            Text(model.storeManager.purchaseButtonLabel)
                        }
                    }
                    .buttonStyle(BrassButtonStyle())
                    .disabled(model.storeManager.isPurchasing || model.storeManager.isRestoring)
                    .accessibilityLabel("Unlock Foldfleet, one-time purchase")

                    Button("Restore Purchase") {
                        Task { await model.storeManager.restore() }
                    }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(model.storeManager.isPurchasing || model.storeManager.isRestoring)

                    if model.storeManager.isRestoring {
                        ProgressView("Checking for previous purchases…")
                            .font(FleetFonts.body(14))
                            .foregroundStyle(FleetColors.paper.opacity(0.75))
                    }

                    if let error = model.storeManager.errorMessage {
                        Text(error)
                            .font(FleetFonts.body(14))
                            .foregroundStyle(FleetColors.hit)
                            .multilineTextAlignment(.center)
                            .accessibilityLabel("Game status")
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }

                Button("Back to menu") { onClose() }
                    .buttonStyle(GhostButtonStyle())

                Text("Your 5-minute free trial does not renew. If you already bought Foldfleet, use Restore Purchase — you won't be charged again.")
                    .font(FleetFonts.mono(12))
                    .foregroundStyle(FleetColors.paper.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .oceanBackground()
        .interactiveDismissDisabled(true)
        .task {
            // Refresh the product (and its localized price) whenever the
            // paywall appears, in case the first load at launch failed.
            await model.storeManager.loadProduct()
        }
        .accessibilityLabel("Unlock Foldfleet. Your free trial has ended.")
    }
}

import Foundation
import StoreKit

// MARK: - StoreManager
//
// The single source of truth for permanent ownership of Foldfleet.
//
// Product:  com.foldfleet.fullgame — NON-CONSUMABLE, one-time $14.99.
// Payment is always Apple's StoreKit purchase sheet; there is no other
// payment system in the app (no Stripe, no PayPal, no web checkout).
//
// Rules this class enforces:
//   * The game is unlocked ONLY after a VERIFIED StoreKit transaction.
//     An unverified transaction never unlocks anything.
//   * Entitlements are re-checked from StoreKit on launch and on restore.
//     A UserDefaults flag is never used as proof of ownership — there is
//     none stored anywhere. Transaction.currentEntitlements is the
//     authority, including refunds/revocations (a revoked transaction
//     removes the unlock).
//   * Errors shown to the player are plain-language; StoreKit internals
//     are never exposed in the UI.
//   * The transaction listener runs from launch, so purchases completed
//     outside the paywall (App Store, another device, an approved
//     Ask-to-Buy) are still picked up and finished.
//
// This file needs StoreKit, so it can only compile and run in Xcode / on
// iOS — it is deliberately excluded from the Linux Swift checks, which
// cover only the pure-logic files (see scripts/swift_check/run.sh).

@MainActor
@Observable
public final class StoreManager {
    public static let fullGameProductID = "com.foldfleet.fullgame"

    /// The StoreKit product, once loaded. The paywall shows
    /// `product.displayPrice` (localized, in the customer's currency),
    /// never a hardcoded price.
    public private(set) var product: Product?

    /// Permanent ownership, from verified StoreKit entitlements only.
    public private(set) var isUnlocked = false

    public private(set) var isLoadingProduct = false
    public private(set) var isPurchasing = false
    public private(set) var isRestoring = false

    /// Plain-language message for the paywall, or nil. Never contains
    /// StoreKit error details.
    public private(set) var errorMessage: String?

    /// "Unlock Foldfleet — $14.99" in the customer's own currency once the
    /// product has loaded; "$14.99" is only the fallback shown while the
    /// product is still loading (the App Store Connect price is $14.99).
    public var purchaseButtonLabel: String {
        "Unlock Foldfleet — \(product?.displayPrice ?? "$14.99")"
    }

    private var updatesTask: Task<Void, Never>?

    public init() {
        startListeningForTransactions()
        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    isolated deinit {
        updatesTask?.cancel()
    }

    public func clearError() {
        errorMessage = nil
    }

    // MARK: Product

    /// Load the product from StoreKit. Fails softly (the paywall stays
    /// usable and shows the fallback price) when the App Store is
    /// unreachable or the product is not configured yet in App Store
    /// Connect — the app never crashes over this.
    public func loadProduct() async {
        isLoadingProduct = true
        errorMessage = nil
        defer { isLoadingProduct = false }
        do {
            let products = try await Product.products(for: [Self.fullGameProductID])
            product = products.first
            if product == nil {
                errorMessage = "The full-game purchase isn't available right now. Please try again later."
            }
        } catch {
            errorMessage = "Couldn't reach the App Store. Check your connection and try again."
        }
    }

    // MARK: Entitlements (the authority)

    /// Re-read current entitlements from StoreKit. Called on launch, after
    /// a purchase, after a restore, and when the app returns to the
    /// foreground. Works offline from StoreKit's local cache.
    public func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            // A refunded/revoked transaction must not keep the game unlocked.
            guard transaction.productID == Self.fullGameProductID,
                  transaction.revocationDate == nil else { continue }
            owned = true
        }
        isUnlocked = owned
    }

    // MARK: Purchase

    /// Run Apple's purchase sheet for the full game. Unlocks ONLY on a
    /// verified transaction for our product ID.
    public func purchase() async {
        if product == nil {
            await loadProduct()
        }
        guard let product else {
            errorMessage = "The full-game purchase isn't available right now. Please try again later."
            return
        }
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    guard transaction.productID == Self.fullGameProductID else { return }
                    // Verified: finish the transaction and re-read
                    // entitlements — that is what flips isUnlocked.
                    await transaction.finish()
                    await refreshEntitlements()
                case .unverified:
                    // Never unlock on an unverified transaction, and do not
                    // finish it. The player has not been charged by us.
                    errorMessage = "We couldn't verify that purchase. Please try again — you have not been charged."
                }
            case .pending:
                // Ask to Buy / parental approval / payment authorisation
                // still in flight. Nothing is charged yet; the transaction
                // listener will unlock the game when it is approved.
                errorMessage = "Your purchase is waiting for approval. It will unlock automatically once it's approved."
            case .userCancelled:
                // Silent: the player just changed their mind.
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "The purchase couldn't be completed. Check your connection and try again."
        }
    }

    // MARK: Restore

    /// Restore a previous purchase on this Apple Account. Syncs with the
    /// App Store, then re-reads entitlements. Never charges anyone.
    public func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isUnlocked {
                errorMessage = "No previous Foldfleet purchase was found for this Apple Account."
            }
        } catch {
            errorMessage = "Couldn't check for previous purchases. Check your connection and try again."
        }
    }

    // MARK: Transaction listener

    /// Listen from launch for transactions that arrive outside the paywall
    /// (App Store purchase, another device, approved Ask to Buy). Verified
    /// transactions for our product unlock the game and are finished;
    /// unverified ones are ignored and never unlock.
    private func startListeningForTransactions() {
        updatesTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                guard await transaction.productID == Self.fullGameProductID else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
    }
}

import Foundation
import StoreKit

// Source-only bridge. All StoreKit state is MainActor isolated; polling uses a lock.
@objc(NWStoreKitBridge) public final class NWStoreKitBridge: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    @MainActor private var productID = ""
    @MainActor private var listener: Task<Void, Never>?
    @MainActor private var deliveries: [String: Transaction] = [:]
    @MainActor private var purchaseBusy = false
    @MainActor private var revision = 0
    @MainActor private var refreshSequence = 0

    private func emit(_ event: [String: Any]) {
        guard let bytes = try? JSONSerialization.data(withJSONObject: event),
              let json = String(data: bytes, encoding: .utf8) else { return }
        lock.lock(); events.append(json); lock.unlock()
    }
    @objc public func popEvent() -> String {
        lock.lock(); defer { lock.unlock() }
        return events.isEmpty ? "" : events.removeFirst()
    }
    @objc public func configure(_ identifier: String) {
        Task { @MainActor [self] in
            guard self.productID.isEmpty, !identifier.isEmpty else { return }
            self.productID = identifier
            self.emit(["kind":"configured"])
            self.listener = Task { @MainActor [weak self] in
                for await result in Transaction.updates {
                    guard let self else { return }
                    await self.deliver(result)
                }
            }
            for await result in Transaction.unfinished { await self.deliver(result) }
            _ = await self.refreshEntitlement()
        }
    }
    @MainActor private func deliver(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            emit(["kind":"error", "operation":"verification", "message":"Purchase could not be verified."])
            return // Never unlock or finish an unverified transaction.
        }
        guard transaction.productID == productID, transaction.productType == .nonConsumable else { return }
        revision += 1
        let token = UUID().uuidString
        deliveries[token] = transaction
        emit(["kind":"entitlement", "product_id":productID, "verified":true,
              "owned":transaction.revocationDate == nil, "delivery_token":token])
    }
    @objc public func acknowledge(_ token: String) {
        Task { @MainActor in
            guard let transaction = self.deliveries.removeValue(forKey: token) else { return }
            await transaction.finish() // Godot has applied and emitted the entitlement first.
        }
    }
    @objc public func refresh() { Task { @MainActor in _ = await self.refreshEntitlement() } }
    @MainActor private func refreshEntitlement() async -> Bool {
        guard !productID.isEmpty else { return false }
        refreshSequence += 1
        let sequence = refreshSequence
        let startingRevision = revision
        var owned = false
        var unverifiable = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == productID && transaction.productType == .nonConsumable && transaction.revocationDate == nil { owned = true }
            case .unverified(let transaction, _):
                if transaction.productID == productID { unverifiable = true }
            }
        }
        // A concurrent purchase/update supersedes this snapshot.
        guard revision == startingRevision, refreshSequence == sequence else { return false }
        if unverifiable {
            emit(["kind":"error", "operation":"verification", "message":"Entitlement could not be verified."])
            return false
        } else {
            emit(["kind":"entitlement", "product_id":productID, "verified":true, "owned":owned])
            return true
        }
    }
    @objc public func queryProduct() {
        Task { @MainActor in
            do {
                guard let product = try await Product.products(for: [self.productID]).first,
                      product.id == self.productID, product.type == .nonConsumable else {
                    throw NSError(domain:"NineweaveStoreKit", code:1, userInfo:[NSLocalizedDescriptionKey:"Remove Ads product is unavailable."])
                }
                self.emit(["kind":"product", "product_id":product.id, "price":product.displayPrice, "name":product.displayName])
            } catch { self.emit(["kind":"error", "operation":"product", "message":error.localizedDescription]) }
        }
    }
    @objc public func purchase() {
        Task { @MainActor in
            guard !self.purchaseBusy, !self.productID.isEmpty else { return }
            self.purchaseBusy = true
            defer { self.purchaseBusy = false }
            do {
                guard let product = try await Product.products(for: [self.productID]).first,
                      product.id == self.productID, product.type == .nonConsumable else {
                    throw NSError(domain:"NineweaveStoreKit", code:1, userInfo:[NSLocalizedDescriptionKey:"Remove Ads product is unavailable."])
                }
                switch try await product.purchase() {
                case .success(let result): await self.deliver(result)
                case .pending: self.emit(["kind":"purchase", "state":"pending"])
                case .userCancelled: self.emit(["kind":"purchase", "state":"cancelled"])
                @unknown default: self.emit(["kind":"error", "operation":"purchase", "message":"Unknown purchase result."])
                }
            } catch { self.emit(["kind":"error", "operation":"purchase", "message":error.localizedDescription]) }
        }
    }
    @objc public func restore() {
        Task { @MainActor in
            do {
                try await AppStore.sync()
                if await self.refreshEntitlement() {
                    self.emit(["kind":"restore", "state":"complete"])
                } else {
                    self.emit(["kind":"restore", "state":"unconfirmed"])
                }
            }
            catch { self.emit(["kind":"error", "operation":"restore", "message":error.localizedDescription]) }
        }
    }
    @objc public func shutdown() {
        Task { @MainActor in self.listener?.cancel(); self.listener = nil }
    }
}

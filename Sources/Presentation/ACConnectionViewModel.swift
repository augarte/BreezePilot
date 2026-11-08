import Observation
import Foundation

@MainActor @Observable
final class ACConnectionViewModel {
    enum Manufacturer: String, CaseIterable {
        case daikin = "Daikin"
        case xiaomi = "Xiaomi / Mijia"
    }

    var draft: SavedAC {
        didSet { if draft.address != oldValue.address { resetCheck() } }
    }
    var manufacturer: Manufacturer {
        didSet { if manufacturer != oldValue { resetCheck() } }
    }
    var tokenInput = "" {
        didSet { if tokenInput != oldValue { resetCheck() } }
    }
    private(set) var checking = false
    private(set) var result: String?
    private var verifiedProfile: XiaomiProfile?
    private let library: ACLibrary
    private let devices: ACDevices

    init(unit: SavedAC, library: ACLibrary, devices: ACDevices) {
        draft = unit
        manufacturer = unit.xiaomi == nil ? .daikin : .xiaomi
        self.library = library
        self.devices = devices
    }

    var existing: Bool { library.units.contains { $0.id == draft.id } }
    var address: LocalAddress? { LocalAddress(draft.address) }
    var duplicate: Bool { address.map { library.hasUnit(at: $0, except: draft.id) } ?? false }
    var name: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasNewToken: Bool { !tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var canCheck: Bool {
        guard address != nil, !checking, !duplicate else { return false }
        return manufacturer == .daikin || XiaomiToken(tokenInput) != nil || (draft.xiaomi != nil && !hasNewToken)
    }

    var canSave: Bool {
        guard !name.isEmpty, let address, !checking, !duplicate else { return false }
        return manufacturer == .daikin || verifiedProfile != nil ||
            (draft.xiaomi != nil && address.value == savedAddress && !hasNewToken)
    }

    private var savedAddress: String? { library.units.first { $0.id == draft.id }?.address }

    private func resetCheck() {
        verifiedProfile = nil
        result = nil
    }

    func check() async {
        guard canCheck, let address else { return }
        checking = true
        resetCheck()
        defer { checking = false }
        do {
            if manufacturer == .xiaomi {
                if let token = XiaomiToken(tokenInput) {
                    verifiedProfile = try await devices.xiaomiSetup.check(address: address, token: token)
                } else if let profile = draft.xiaomi {
                    _ = try await devices.make(draft, address).readStatus()
                    verifiedProfile = profile
                }
                result = "Connected. The AC returned its local status."
            } else {
                _ = try await devices.make(draft, address).readStatus()
                result = "Connected. The AC responded."
            }
        } catch is CancellationError {
            return
        } catch {
            result = error.localizedDescription
        }
    }

    func save() -> Bool {
        guard canSave, let address else { return false }
        if manufacturer == .xiaomi, let profile = verifiedProfile {
            if let token = XiaomiToken(tokenInput) {
                do {
                    try devices.xiaomiSetup.save(token, for: draft.id)
                } catch {
                    result = error.localizedDescription
                    return false
                }
            }
            draft.xiaomi = profile
        }
        draft.name = name
        draft.address = address.value
        library.save(draft)
        return true
    }

    func remove() -> Bool {
        do {
            if draft.xiaomi != nil { try devices.xiaomiSetup.removeToken(for: draft.id) }
            library.removeUnit(draft.id)
            return true
        } catch {
            result = error.localizedDescription
            return false
        }
    }
}

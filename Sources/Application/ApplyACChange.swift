import Foundation

struct ApplyACChange: Sendable {
    struct Result: Sendable {
        let status: ACStatus?
        var message: String? = nil
    }

    let device: any ACDevice
    var unitID: UUID? = nil
    var waitForReadback: @Sendable () async throws -> Void = {
        try await Task.sleep(for: .milliseconds(500))
    }

    func callAsFunction(_ change: ACChange) async throws -> Result {
        // Daikin writes several settings together. Serialize each unit’s read, write, and readback.
        try await ACCommandLock.withLock(unitID?.uuidString) {
            try await apply(change)
        }
    }

    private func apply(_ change: ACChange) async throws -> Result {
        let fresh = try await device.readStatus()
        if change.isConfirmed(by: fresh) { return Result(status: fresh) }
        if let message = change.rejection(in: fresh) {
            return Result(status: fresh, message: message)
        }

        // A lost acknowledgement can follow a successful write. Read back without repeating it.
        do {
            try await device.write(change, current: fresh)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Readback is authoritative even when the response to the write is ambiguous.
        }

        var latest: ACStatus?
        for _ in 0..<4 {
            try await waitForReadback()
            guard let status = try? await device.readStatus() else { continue }
            latest = status
            if change.isConfirmed(by: status) { return Result(status: status) }
        }
        try Task.checkCancellation()
        return Result(status: latest, message: ACDeviceError.unconfirmed.localizedDescription)
    }
}

enum ACCommandLock {
    static func withLock<Value>(_ key: String?, operation: () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        guard let key, let container = ACWidgetStore.container else { return try await operation() }
        let url = container.appendingPathComponent("\(key).lock")
        let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw ACDeviceError.commandInProgress }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw ACDeviceError.commandInProgress
        }
        return try await operation()
    }
}

private extension ACChange {
    func isConfirmed(by status: ACStatus) -> Bool {
        switch self {
        case let .target(target, _, mode):
            status.isOn && status.mode == mode && status.isTemperatureMode && status.target == target
        case let .power(isOn):
            status.isOn == isOn
        case let .mode(mode):
            status.isOn && status.mode == mode
        case let .fan(speed, mode):
            status.isOn && status.mode == mode && status.fan?.selected == speed
        case let .special(operation):
            status.isOn && status.features.confirms(operation)
        case let .streamer(isOn):
            status.isOn && status.features.streamer == isOn
        }
    }

    func rejection(in status: ACStatus) -> String? {
        switch self {
        case let .target(target, previous, mode):
            if status.target != previous {
                return "The target changed elsewhere. Adjust the new value to continue."
            }
            return status.mode == mode && status.canAdjust && status.permitsTarget(target)
                ? nil : "The AC’s current settings no longer allow that temperature change."
        case .power:
            return status.powerWritable ? nil : "This AC doesn’t allow local power changes."
        case let .mode(mode):
            return status.isOn && status.availableModes.contains(mode)
                ? nil : "The AC’s current settings no longer allow that mode."
        case let .fan(speed, mode):
            return status.isOn && status.mode == mode && status.fan?.available.contains(speed) == true
                ? nil : "The AC’s current settings no longer allow that fan speed."
        case let .special(operation):
            return status.isOn && status.features.supports(operation)
                ? nil : "The AC’s current settings no longer allow that operation."
        case .streamer:
            return status.isOn && status.features.streamer != nil
                ? nil : "The AC’s current settings no longer allow Streamer."
        }
    }
}

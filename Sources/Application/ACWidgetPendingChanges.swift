import Foundation

/// Power and fan taps from the widget, queued so the widget can answer at once.
///
/// The intent only records the tap here and returns, so the widget redraws with the new value straight
/// away. A background activity then writes the final value to the AC after a short quiet period, which
/// means a run of taps (fan 1 to 5) becomes a single command. When the AC confirms, the entry is removed
/// and the confirmed status takes over. When it fails, the entry is removed and the widget falls back to
/// the AC's real state.
struct ACWidgetPendingChanges: Sendable {
    let directory: URL
    var quietPeriod = ACStatus.temperatureEditDelay
    var powerQuietPeriod: TimeInterval = 0.3

    // Leave room for an in-flight command, but never apply or show a change from long ago.
    static let lifetime: TimeInterval = 30
    private static let refreshLifetime: TimeInterval = 25
    // A worker normally starts within a second. A change older than this was probably left behind by
    // a process that was suspended, so the next timeline reload applies it instead.
    static let staleAfter: TimeInterval = 6

    struct FanTarget: Codable, Equatable, Sendable {
        let speed: FanSpeed
        let mode: ClimateMode
    }

    struct Field<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
        let value: Value
        let token: UUID
        let updatedAt: Date

        var isActive: Bool { Date.now.timeIntervalSince(updatedAt) < ACWidgetPendingChanges.lifetime }
    }

    struct Change: Codable, Equatable, Sendable {
        var power: Field<Bool>?
        var fan: Field<FanTarget>?
        /// Set when the background activity ran out of time, so the next timeline reload applies the rest.
        var needsTimelineWrite: Bool?

        var isEmpty: Bool { power == nil && fan == nil }
    }

    enum Kind: Sendable {
        case power(Bool)
        case fan(FanTarget)
    }

    private struct Edit {
        let change: ACChange
        let token: UUID
        let updatedAt: Date
        let quietPeriod: TimeInterval
    }

    // MARK: Queue

    func enqueue(_ kind: Kind, for unitID: UUID) {
        let token = UUID()
        update(unitID) { change in
            var draft = change ?? Change()
            switch kind {
            case let .power(isOn):
                draft.power = Field(value: isOn, token: token, updatedAt: .now)
            case let .fan(target):
                draft.fan = Field(value: target, token: token, updatedAt: .now)
            }
            draft.needsTimelineWrite = nil
            change = draft
        }
    }

    func power(for unitID: UUID) -> Bool? {
        guard let field = read(unitID)?.power, field.isActive else { return nil }
        return field.value
    }

    func fan(for unitID: UUID) -> FanSpeed? {
        guard let field = read(unitID)?.fan, field.isActive else { return nil }
        return field.value.speed
    }

    func hasPending(for unitID: UUID) -> Bool {
        power(for: unitID) != nil || fan(for: unitID) != nil
    }

    func needsTimelineWrite(for unitID: UUID) -> Bool {
        guard let change = read(unitID), hasPending(for: unitID) else { return false }
        if change.needsTimelineWrite == true { return true }
        return [change.power?.updatedAt, change.fan?.updatedAt].contains {
            $0.map { Date.now.timeIntervalSince($0) > Self.staleAfter } ?? false
        }
    }

    func handOffToTimeline(for unitID: UUID) {
        update(unitID) { change in
            if change?.isEmpty == false { change?.needsTimelineWrite = true }
        }
    }

    // MARK: Applying

    /// Writes queued changes, one setting at a time, until none are left. Returns the last confirmed status.
    func applyPending(for unitID: UUID, device: any ACDevice,
                      waitForReadback: @escaping @Sendable () async throws -> Void = {
                          try await Task.sleep(for: .milliseconds(500))
                      }) async -> ACStatus? {
        var latest: ACStatus?
        defer { ACWidgetStore.reload() }

        while !Task.isCancelled, let edit = nextEdit(for: unitID) {
            ACWidgetDiagnostics.log("applying \(edit.change)")
            do {
                let remaining = edit.quietPeriod - Date.now.timeIntervalSince(edit.updatedAt)
                if remaining > 0 {
                    try await Task.sleep(for: .seconds(remaining))
                    continue
                }
                let status = try await ACCommandLock.withLock(unitID.uuidString) {
                    // A later tap may have replaced this value while we waited for the lock.
                    guard nextEdit(for: unitID)?.token == edit.token else { return nil as ACStatus? }
                    do {
                        let result = try await ApplyACChange(device: device, waitForReadback: waitForReadback)(edit.change)
                        ACWidgetStore.cacheStatus(result.status, for: unitID)
                        if let message = result.message { throw Failure(message: message) }
                        guard let status = result.status else { throw ACDeviceError.unconfirmed }
                        ACWidgetDiagnostics.log("apply confirmed")
                        finish(edit.token, for: unitID)
                        ACWidgetStore.recordFailure(nil, for: unitID)
                        return status
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // Roll back: dropping the entry makes the widget show the AC's real state again.
                        ACWidgetDiagnostics.log("apply failed: \(error)")
                        finish(edit.token, for: unitID)
                        ACWidgetStore.recordFailure(error.localizedDescription, for: unitID)
                        return nil
                    }
                }
                if let status { latest = status }
            } catch ACDeviceError.commandInProgress {
                ACWidgetDiagnostics.log("command in progress")
                try? await Task.sleep(for: .milliseconds(100))
            } catch is CancellationError {
                ACWidgetDiagnostics.log("cancelled")
                break
            } catch {
                ACWidgetDiagnostics.log("loop error: \(error)")
                ACWidgetStore.recordFailure(error.localizedDescription, for: unitID)
                clear(unitID)
                break
            }
        }
        return latest
    }

    // Power goes first: a fan speed only makes sense once the AC is on.
    private func nextEdit(for unitID: UUID) -> Edit? {
        guard let change = read(unitID) else { return nil }
        if let power = change.power, power.isActive {
            return Edit(change: .power(power.value), token: power.token, updatedAt: power.updatedAt,
                        quietPeriod: powerQuietPeriod)
        }
        if let fan = change.fan, fan.isActive {
            return Edit(change: .fan(fan.value.speed, mode: fan.value.mode), token: fan.token,
                        updatedAt: fan.updatedAt, quietPeriod: quietPeriod)
        }
        return nil
    }

    private func finish(_ token: UUID, for unitID: UUID) {
        update(unitID) { change in
            guard var draft = change else { return }
            if draft.power?.token == token { draft.power = nil }
            if draft.fan?.token == token { draft.fan = nil }
            change = draft.isEmpty ? nil : draft
        }
    }

    private func clear(_ unitID: UUID) {
        update(unitID) { $0 = nil }
    }

    // MARK: Refresh

    var isRefreshing: Bool {
        guard let data = try? Data(contentsOf: refreshFile),
              let expiresAt = try? JSONDecoder().decode(Date.self, from: data) else { return false }
        return expiresAt > .now
    }

    func beginRefresh() {
        let expiresAt = Date.now.addingTimeInterval(Self.refreshLifetime)
        try? JSONEncoder().encode(expiresAt).write(to: refreshFile, options: .atomic)
    }

    func endRefresh() {
        try? FileManager.default.removeItem(at: refreshFile)
    }

    // MARK: Storage

    private var refreshFile: URL { directory.appendingPathComponent("refresh.pending.json") }

    private func file(_ unitID: UUID) -> URL {
        directory.appendingPathComponent("\(unitID.uuidString).pending.json")
    }

    private func read(_ unitID: UUID) -> Change? {
        guard let data = try? Data(contentsOf: file(unitID)) else { return nil }
        return try? JSONDecoder().decode(Change.self, from: data)
    }

    private func update(_ unitID: UUID, _ edit: (inout Change?) -> Void) {
        // A short, synchronous lock that only protects this file. It never covers a device request.
        let lock = directory.appendingPathComponent("\(unitID.uuidString).pending.lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { return }
        var change = read(unitID)
        let previous = change
        edit(&change)
        guard change != previous else { return }
        if let change {
            try? JSONEncoder().encode(change).write(to: file(unitID), options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: file(unitID))
        }
    }

    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}

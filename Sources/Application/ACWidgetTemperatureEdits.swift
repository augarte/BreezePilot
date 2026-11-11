import Foundation

struct ACWidgetTemperatureEdits: Sendable {
    let directory: URL
    var quietPeriod = ACStatus.temperatureEditDelay

    // Leave room for an in-flight command, but never apply an edit from an old timeline reload.
    private static let maximumAge: TimeInterval = 15

    private struct Edit: Codable, Equatable {
        let id: UUID
        let mode: ClimateMode
        let limits: ClosedRange<Int>
        let step: Int
        var baseline: Int
        var target: Int
        var updatedAt: Date
        var confirmedAt: Date?
        var requiresTimelineWrite: Bool?

        var isPending: Bool { baseline != target }
        var isExpired: Bool { Date.now.timeIntervalSince(updatedAt) >= ACWidgetTemperatureEdits.maximumAge }
    }

    func enqueue(for unitID: UUID, previous: Int, target: Int, mode: ClimateMode,
                 limits: ClosedRange<Int>, observedAt: Date = .distantPast,
                 confirmedTarget: Int? = nil) throws {
        let (delta, overflow) = target.subtractingReportingOverflow(previous)
        let baseline = confirmedTarget ?? previous
        guard !overflow, delta != 0, delta != .min, limits.contains(previous), limits.contains(target),
              limits.contains(baseline) else {
            throw Failure(message: "Choose a temperature supported by the AC.")
        }
        let step = abs(delta)
        try update(unitID) { edit in
            if let draft = edit, baseline != draft.baseline,
               observedAt > max(draft.updatedAt, draft.confirmedAt ?? .distantPast) {
                edit = nil
            }
            if edit == nil || edit?.isExpired == true || edit?.mode != mode ||
                edit?.limits != limits || edit?.step != step {
                edit = Edit(id: UUID(), mode: mode, limits: limits, step: step, baseline: baseline,
                            target: baseline, updatedAt: .now)
            }
            guard var draft = edit else { return }
            if !draft.isPending { draft.requiresTimelineWrite = nil }
            let (next, overflow) = draft.target.addingReportingOverflow(delta)
            if !overflow, limits.contains(next) { draft.target = next }
            draft.updatedAt = .now
            edit = draft
        }
    }

    func pendingTarget(for unitID: UUID) -> Int? {
        guard let edit = read(unitID), edit.isPending, !edit.isExpired else { return nil }
        return edit.target
    }

    func needsTimelineWrite(for unitID: UUID) -> Bool {
        guard let edit = read(unitID), edit.isPending else { return false }
        return edit.requiresTimelineWrite == true || edit.isExpired
    }

    func handOffToTimeline(for unitID: UUID) {
        try? update(unitID) { edit in
            if edit?.isPending == true { edit?.requiresTimelineWrite = true }
        }
    }

    func applyPending(for unitID: UUID, device: any ACDevice,
                      waitForReadback: @escaping @Sendable () async throws -> Void = {
                          try await Task.sleep(for: .milliseconds(500))
                      }) async -> ACStatus? {
        var latest: ACStatus?
        var resolved = false
        defer { if resolved { ACWidgetStore.reload() } }

        while let edit = read(unitID), edit.isPending, !Task.isCancelled {
            do {
                let remaining = quietPeriod - Date.now.timeIntervalSince(edit.updatedAt)
                if remaining > 0 {
                    try await Task.sleep(for: .seconds(remaining))
                    continue
                }

                let status = try await ACCommandLock.withLock(unitID.uuidString) {
                    // A later tap or a different widget may have changed the draft while we waited.
                    guard read(unitID) == edit else { return nil as ACStatus? }
                    do {
                        guard !edit.isExpired else { throw Failure(message: "Temperature change expired. Try again.") }
                        let apply = ApplyACChange(device: device, waitForReadback: waitForReadback)
                        let result = try await apply(.target(edit.target, previous: edit.baseline, mode: edit.mode))
                        ACWidgetStore.cacheStatus(result.status, for: unitID)
                        if let message = result.message { throw Failure(message: message) }
                        guard let status = result.status else { throw ACDeviceError.unconfirmed }
                        try update(unitID) { draft in
                            guard draft?.id == edit.id else { return }
                            draft?.baseline = edit.target
                            draft?.confirmedAt = .now
                        }
                        ACWidgetStore.recordFailure(nil, for: unitID)
                        resolved = true
                        return status
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        try discard(edit, for: unitID)
                        ACWidgetStore.recordFailure(error.localizedDescription, for: unitID)
                        resolved = true
                        return nil
                    }
                }
                if let status {
                    latest = status
                }
            } catch ACDeviceError.commandInProgress {
                // Another timeline, scene, or in-app action may hold the device lock.
                try? await Task.sleep(for: .milliseconds(100))
            } catch is CancellationError {
                break
            } catch {
                ACWidgetStore.recordFailure(error.localizedDescription, for: unitID)
                resolved = true
                break
            }
        }
        return latest
    }

    private func discard(_ edit: Edit, for unitID: UUID) throws {
        try update(unitID) { draft in
            if draft?.id == edit.id { draft = nil }
        }
    }

    private func file(_ unitID: UUID) -> URL {
        directory.appendingPathComponent("\(unitID.uuidString).temperature.json")
    }

    private func read(_ unitID: UUID) -> Edit? {
        guard let data = try? Data(contentsOf: file(unitID)) else { return nil }
        return try? JSONDecoder().decode(Edit.self, from: data)
    }

    private func update(_ unitID: UUID, _ edit: (inout Edit?) -> Void) throws {
        // This short, synchronous lock only protects the file update. It never covers a device request.
        let lock = directory.appendingPathComponent("\(unitID.uuidString).temperature.lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure(message: "Couldn’t save the temperature change.") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw Failure(message: "Couldn’t save the temperature change.") }
        var draft = read(unitID)
        let previous = draft
        edit(&draft)
        guard draft != previous else { return }
        if let draft {
            try JSONEncoder().encode(draft).write(to: file(unitID), options: .atomic)
        } else {
            try FileManager.default.removeItem(at: file(unitID))
        }
    }

    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}

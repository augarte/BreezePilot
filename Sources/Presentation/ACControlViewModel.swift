import Foundation
import Observation

@MainActor @Observable
final class ACControlViewModel {
    private let device: any ACDevice
    private let applyChange: ApplyACChange
    private(set) var status: ACStatus?
    private(set) var updatedAt: Date?
    private(set) var activity: Activity?
    private(set) var message: String?
    private(set) var pendingTarget: Int?
    private var hasCheckedConnection = false
    @ObservationIgnored private var adjustmentTask: Task<Void, Never>?

    var isUpdating: Bool { activity != nil || pendingTarget != nil }
    var isConnecting: Bool { !hasCheckedConnection || activity == .reading }
    var displayedTarget: Int? { pendingTarget ?? status?.target }

    enum Activity {
        case reading
        case writing
    }

    init(device: any ACDevice) {
        self.device = device
        applyChange = ApplyACChange(device: device)
    }

    func canAdjust(by delta: Int) -> Bool {
        activity == nil && status?.adjusted(by: delta, from: pendingTarget) != nil
    }

    func refresh() async {
        guard !isUpdating else { return }
        activity = .reading
        message = nil
        defer {
            hasCheckedConnection = true
            activity = nil
        }

        do {
            receive(try await device.readStatus())
        } catch is CancellationError {
            return
        } catch {
            status = nil
            message = error.localizedDescription
        }
    }

    func adjust(by delta: Int) {
        guard activity == nil, let status, let mode = status.mode,
              let target = status.adjusted(by: delta, from: pendingTarget) else { return }
        adjustmentTask?.cancel()
        adjustmentTask = nil
        message = nil
        pendingTarget = target == status.target ? nil : target
        guard pendingTarget != nil else { return }

        let change = ACChange.target(target, previous: status.target, mode: mode)
        adjustmentTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(750))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.adjustmentTask = nil
            await self.performChange(change)
        }
    }

    func togglePower() async {
        guard !isUpdating, let status, status.powerWritable else { return }
        await performChange(.power(!status.isOn))
    }

    func selectMode(_ mode: ClimateMode) async {
        guard !isUpdating, let status, status.isOn,
              status.mode != mode, status.availableModes.contains(mode) else { return }
        await performChange(.mode(mode))
    }

    func selectFanSpeed(_ speed: FanSpeed) async {
        guard !isUpdating, let status, status.isOn, let fan = status.fan, let mode = status.mode,
              fan.selected != speed, fan.available.contains(speed) else { return }
        await performChange(.fan(speed, mode: mode))
    }

    func selectSpecialOperation(_ operation: SpecialOperation) async {
        guard !isUpdating, let status, status.isOn, status.features.supports(operation),
              !status.features.confirms(operation) else { return }
        await performChange(.special(operation))
    }

    func setStreamer(_ isOn: Bool) async {
        guard !isUpdating, let status, status.isOn,
              let current = status.features.streamer, current != isOn else { return }
        await performChange(.streamer(isOn))
    }

    private func performChange(_ change: ACChange) async {
        activity = .writing
        message = nil
        defer {
            pendingTarget = nil
            activity = nil
        }

        do {
            let result = try await applyChange(change)
            if let status = result.status {
                receive(status)
            } else {
                status = nil
            }
            message = result.message
        } catch is CancellationError {
            status = nil
        } catch {
            status = nil
            message = error.localizedDescription
        }
    }

    private func receive(_ status: ACStatus) {
        self.status = status
        updatedAt = .now
    }
}

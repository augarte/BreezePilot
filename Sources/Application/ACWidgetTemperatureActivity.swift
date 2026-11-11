import Foundation
import os

enum ACWidgetTemperatureActivity {
    private static let active = OSAllocatedUnfairLock(initialState: [UUID: Bool]())

    private struct Activity {
        var started = false
        var finished = false
        var expired = false
        var task: Task<Void, Never>?
    }

    static func schedule(unit: SavedAC, address: LocalAddress, edits: ACWidgetTemperatureEdits) {
        let id = unit.id
        guard edits.pendingTarget(for: id) != nil, !edits.needsTimelineWrite(for: id) else { return }
        let shouldStart = active.withLock { tasks in
            if tasks[id] != nil {
                tasks[id] = true
                return false
            }
            tasks[id] = false
            return true
        }
        guard shouldStart else { return }

        let activity = OSAllocatedUnfairLock(initialState: Activity())
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Apply the Home Screen temperature edit") { expired in
            if expired {
                let handoff = activity.withLock { state in
                    guard !state.finished else { return false }
                    state.expired = true
                    state.task?.cancel()
                    if !state.started { active.withLock { _ = $0.removeValue(forKey: id) } }
                    return true
                }
                if handoff {
                    edits.handOffToTimeline(for: id)
                    ACWidgetStore.reload()
                }
                return
            }

            guard activity.withLock({ state in
                guard !state.expired else { return false }
                state.started = true
                return true
            }) else { return }

            // Keep the system assertion alive until the async work finishes.
            // This waits on Foundation's activity queue, rather than on a Swift task executor.
            let finished = DispatchSemaphore(value: 0)
            let task = Task.detached(priority: .userInitiated) {
                defer { finished.signal() }
                let device = ACDevices.local.make(unit, address)
                _ = await edits.applyPending(for: id, device: device)
            }
            activity.withLock { state in
                state.task = task
                if state.expired { task.cancel() }
            }
            finished.wait()
            let canContinue = activity.withLock { state in
                state.finished = true
                state.task = nil
                return !state.expired
            }
            let receivedAnotherTap = active.withLock { $0.removeValue(forKey: id) == true }
            // A tap may have arrived just after the worker observed an empty queue.
            if canContinue && receivedAnotherTap && !edits.needsTimelineWrite(for: id) {
                schedule(unit: unit, address: address, edits: edits)
            }
        }
    }
}

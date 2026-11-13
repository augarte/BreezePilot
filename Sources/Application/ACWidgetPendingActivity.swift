import Foundation
import os

/// Runs widget work after the intent has returned, so the widget can redraw first.
enum ACWidgetPendingActivity {
    private static let active = OSAllocatedUnfairLock(initialState: [UUID: Bool]())

    private struct Activity {
        var started = false
        var finished = false
        var expired = false
        var task: Task<Void, Never>?
    }

    /// Applies queued power and fan changes for one AC.
    static func schedule(unit: SavedAC, address: LocalAddress, pending: ACWidgetPendingChanges) {
        let id = unit.id
        guard pending.hasPending(for: id), !pending.needsTimelineWrite(for: id) else { return }
        let shouldStart = active.withLock { tasks in
            if tasks[id] != nil {
                tasks[id] = true // The running worker will pick up this tap.
                return false
            }
            tasks[id] = false
            return true
        }
        guard shouldStart else { return }

        run(reason: "Apply the Home Screen change", onExpire: {
            pending.handOffToTimeline(for: id)
            ACWidgetStore.reload()
        }, onSkipped: {
            active.withLock { _ = $0.removeValue(forKey: id) }
        }, work: {
            let device = ACDevices.local.make(unit, address)
            _ = await pending.applyPending(for: id, device: device)
        }, onFinished: { canContinue in
            let receivedAnotherTap = active.withLock { $0.removeValue(forKey: id) == true }
            // A tap may have arrived just after the worker saw an empty queue.
            if canContinue && receivedAnotherTap { schedule(unit: unit, address: address, pending: pending) }
        })
    }

    /// Reads every saved AC in the background while the widget shows "Refreshing".
    static func refresh(catalog: [WidgetAC], pending: ACWidgetPendingChanges) {
        run(reason: "Refresh the Home Screen widget", onExpire: {
            pending.endRefresh()
            ACWidgetStore.reload()
        }, onSkipped: {}, work: {
            let started = ContinuousClock.now
            await withTaskGroup(of: Void.self) { group in
                for item in catalog {
                    guard let address = LocalAddress(item.unit.address) else { continue }
                    group.addTask {
                        let status = try? await ACDevices.local.make(item.unit, address).readStatus()
                        ACWidgetStore.cacheStatus(status, for: item.unit.id)
                        // A reading that works means an earlier failure no longer applies.
                        if status != nil { ACWidgetStore.recordFailure(nil, for: item.unit.id) }
                    }
                }
            }
            // A fast local read would otherwise flash the indicator too briefly to notice.
            let elapsed = ContinuousClock.now - started
            if elapsed < .milliseconds(1_200) { try? await Task.sleep(for: .milliseconds(1_200) - elapsed) }
            pending.endRefresh()
            ACWidgetStore.reload()
        }, onFinished: { _ in })
    }

    private static func run(
        reason: String,
        onExpire: @escaping @Sendable () -> Void,
        onSkipped: @escaping @Sendable () -> Void,
        work: @escaping @Sendable () async -> Void,
        onFinished: @escaping @Sendable (_ canContinue: Bool) -> Void
    ) {
        let activity = OSAllocatedUnfairLock(initialState: Activity())
        ACWidgetDiagnostics.log("activity requested: \(reason)")
        ProcessInfo.processInfo.performExpiringActivity(withReason: reason) { expired in
            ACWidgetDiagnostics.log("activity callback expired=\(expired): \(reason)")
            if expired {
                let handoff = activity.withLock { state in
                    guard !state.finished else { return false }
                    state.expired = true
                    state.task?.cancel()
                    if !state.started { onSkipped() }
                    return true
                }
                if handoff { onExpire() }
                return
            }

            guard activity.withLock({ state in
                guard !state.expired else { return false }
                state.started = true
                return true
            }) else { return }

            // Keep the system assertion alive until the async work finishes.
            let finished = DispatchSemaphore(value: 0)
            let task = Task.detached(priority: .userInitiated) {
                defer { finished.signal(); ACWidgetDiagnostics.log("work finished: \(reason)") }
                await work()
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
            onFinished(canContinue)
        }
    }
}

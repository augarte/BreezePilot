import WidgetKit

struct ACWidgetEntry: TimelineEntry {
    let date: Date
    let readings: [ACWidgetReading]
    var hasSavedUnits = true
    var isRefreshing = false

    /// About how long a local AC takes to apply a change. After this the widget stops saying "Applying".
    static let settleDelay: TimeInterval = 2.5

    var isTransient: Bool { isRefreshing || readings.contains(where: \.isApplying) }

    /// The entry shown once the AC should have applied the taps. It carries the values that were asked for, with
    /// the buttons working again, because WidgetKit is slow to run a timeline reload after the work is done.
    /// The next real reload replaces it with what the AC reports.
    func settled(at date: Date) -> Self {
        ACWidgetEntry(date: date, readings: readings.map(\.expected), hasSavedUnits: hasSavedUnits, isRefreshing: false)
    }

    static func sample(count: Int, isOn: Bool = true, isAvailable: Bool = true,
                       includesPoweredOffUnit: Bool = false) -> Self {
        let samples: [(room: String, target: Int, fan: FanSpeed)] = [
            ("Living Room", 48, .two),
            ("Bedroom", 47, .one),
            ("Office", 50, .three),
            ("Guest Room", 48, .four)
        ]
        let readings = samples.prefix(count).enumerated().map { index, sample in
            let unit = WidgetAC(unit: SavedAC(name: "\(sample.room) AC"), roomName: sample.room)
            return ACWidgetReading(
                unit: AirConditionerEntity(unit),
                status: isAvailable
                    ? ACStatus(isOn: isOn && !(includesPoweredOffUnit && index == 2),
                               mode: .cool, availableModes: [.cool],
                               room: RoomConditions(temperature: 26, humidity: 55),
                               target: sample.target, limits: 36...60,
                               fan: ACFan(selected: sample.fan, available: FanSpeed.daikin),
                               features: ACFeatures(boost: nil, econo: nil, streamer: nil))
                    : nil
            )
        }
        return ACWidgetEntry(date: .now, readings: readings)
    }
}

struct ACWidgetReading: Identifiable {
    let unit: AirConditionerEntity
    var status: ACStatus?
    var failure: String?
    var observedAt = Date.now
    var pendingTemperature: Int?
    var pendingPower: Bool?
    var pendingFan: FanSpeed?
    /// Cleared on the settled entry, so "Applying" never outlives the work that would end it.
    var showsProgress = true

    var id: UUID { unit.id }

    /// A tapped change the AC has not confirmed yet.
    var isApplying: Bool { pendingTemperature != nil || pendingPower != nil || pendingFan != nil }

    /// The status the buttons work from. A power tap counts at once, so the temperature buttons are usable
    /// as soon as the widget shows the AC on, not only after the AC has confirmed it.
    var controlStatus: ACStatus? {
        status.map { $0.expecting(power: pendingPower) }
    }

    /// The reading with every tapped change applied and nothing left pending.
    var expected: ACWidgetReading {
        var reading = self
        reading.status = status?.expecting(power: pendingPower, target: pendingTemperature, fan: pendingFan)
        reading.pendingPower = nil
        reading.pendingTemperature = nil
        reading.pendingFan = nil
        reading.showsProgress = false
        return reading
    }
}

struct ACWidgetTimeline: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ACWidgetEntry {
        let count = switch context.family {
        case .systemLarge: 4
        case .systemMedium: 2
        default: 1
        }
        return .sample(count: count)
    }

    func snapshot(for configuration: ACWidgetConfiguration, in context: Context) async -> ACWidgetEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entry(for: configuration, family: context.family)
    }

    func timeline(for configuration: ACWidgetConfiguration, in context: Context) async -> Timeline<ACWidgetEntry> {
        let entry = await entry(for: configuration, family: context.family)
        if entry.isTransient {
            // Reloads asked for from the extension can take many seconds, or never come. So the timeline keeps
            // itself moving: the indicator is dropped on schedule, and the widget asks to run again to pick up
            // the real result.
            let settle = entry.date.addingTimeInterval(ACWidgetEntry.settleDelay)
            return Timeline(entries: [entry, entry.settled(at: settle)], policy: .after(entry.date.addingTimeInterval(3)))
        }
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(900)))
    }

    private func entry(for configuration: ACWidgetConfiguration, family: WidgetFamily) async -> ACWidgetEntry {
        let catalog = ACWidgetStore.catalog
        let units = configuration.units(in: family, catalog: catalog)
        let edits = ACWidgetStore.container.map { ACWidgetTemperatureEdits(directory: $0) }
        let pending = ACWidgetStore.pending
        let refreshing = pending?.isRefreshing ?? false
        // While a change or refresh is in flight the intent owns the AC, so show the last known status.
        let holdingStatus = refreshing || units.contains {
            edits?.pendingTarget(for: $0.unit.id) != nil || pending?.hasPending(for: $0.unit.id) == true
        }
        let readings = await withTaskGroup(of: (Int, ACWidgetReading).self) { group in
            for (index, item) in units.enumerated() {
                group.addTask {
                    let id = item.unit.id
                    let status: ACStatus?
                    let observedAt: Date
                    let handOff = edits?.needsTimelineWrite(for: id) == true || pending?.needsTimelineWrite(for: id) == true
                    if holdingStatus, !handOff,
                       // Redraw from the last status however old it is, rather than waiting on the AC.
                       let cached = ACWidgetStore.cachedStatus(for: id, maxAge: .infinity) {
                        status = cached.status
                        observedAt = cached.observedAt
                    } else if !handOff,
                              let fresh = ACWidgetStore.cachedStatus(for: id, maxAge: 10) {
                        // A command or refresh just confirmed this status, so don't ask the AC again.
                        status = fresh.status
                        observedAt = fresh.observedAt
                    } else if let address = LocalAddress(item.unit.address) {
                        let device = ACDevices.local.make(item.unit, address)
                        if let edits, edits.needsTimelineWrite(for: id),
                           let updated = await edits.applyPending(for: id, device: device) {
                            status = updated
                        } else if let pending, pending.needsTimelineWrite(for: id),
                                  let updated = await pending.applyPending(for: id, device: device) {
                            status = updated
                        } else {
                            status = try? await device.readStatus()
                        }
                        observedAt = .now
                        ACWidgetStore.cacheStatus(status, for: id, observedAt: observedAt)
                    } else {
                        status = nil
                        observedAt = .now
                    }
                    let reading = ACWidgetReading(unit: AirConditionerEntity(item), status: status,
                                                  failure: ACWidgetStore.lastFailure(for: id), observedAt: observedAt,
                                                  pendingTemperature: edits?.pendingTarget(for: id),
                                                  pendingPower: pending?.power(for: id),
                                                  pendingFan: pending?.fan(for: id))
                    return (index, reading)
                }
            }
            var readings: [(Int, ACWidgetReading)] = []
            for await reading in group { readings.append(reading) }
            return readings.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        ACWidgetDiagnostics.log("timeline hold=\(holdingStatus) refreshing=\(refreshing) applying=\(readings.filter(\.isApplying).count) failures=\(readings.compactMap(\.failure))")
        return ACWidgetEntry(date: .now, readings: readings,
                             hasSavedUnits: !catalog.isEmpty, isRefreshing: refreshing)
    }
}

import WidgetKit

struct ACWidgetEntry: TimelineEntry {
    let date: Date
    let readings: [ACWidgetReading]
    var hasSavedUnits = true

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
    let status: ACStatus?
    var failure: String?
    var observedAt = Date.now

    var id: UUID { unit.id }
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
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(900)))
    }

    private func entry(for configuration: ACWidgetConfiguration, family: WidgetFamily) async -> ACWidgetEntry {
        let catalog = ACWidgetStore.catalog
        let units = configuration.units(in: family, catalog: catalog)
        let readings = await withTaskGroup(of: (Int, ACWidgetReading).self) { group in
            for (index, item) in units.enumerated() {
                group.addTask {
                    let status: ACStatus?
                    if let address = LocalAddress(item.unit.address) {
                        let device = ACDevices.local.make(item.unit, address)
                        if let directory = ACWidgetStore.container,
                           let updated = await ACWidgetTemperatureEdits(directory: directory)
                            .applyPending(for: item.unit.id, device: device) {
                            status = updated
                        } else {
                            status = try? await device.readStatus()
                        }
                    } else {
                        status = nil
                    }
                    let reading = ACWidgetReading(unit: AirConditionerEntity(item), status: status,
                                                  failure: ACWidgetStore.lastFailure(for: item.unit.id))
                    return (index, reading)
                }
            }
            var readings: [(Int, ACWidgetReading)] = []
            for await reading in group { readings.append(reading) }
            return readings.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        return ACWidgetEntry(date: .now, readings: readings,
                             hasSavedUnits: !catalog.isEmpty)
    }
}

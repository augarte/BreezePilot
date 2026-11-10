import Foundation

struct LocalAddress: Equatable, Sendable {
    let value: String

    init?(_ input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { part -> UInt8? in
            guard let number = UInt8(part), String(number) == part else { return nil }
            return number
        }
        guard parts.count == 4, octets.count == 4 else { return nil }

        switch (octets[0], octets[1], octets[2]) {
        case (10, _, _), (172, 16...31, _), (192, 168, _), (169, 254, 1...254):
            self.value = value
        default:
            return nil
        }
    }
}

struct ACStatus: Sendable {
    static let temperatureEditDelay: TimeInterval = 0.75

    let isOn: Bool
    let mode: ClimateMode?
    let availableModes: [ClimateMode]
    let room: RoomConditions
    let target: Int?
    let limits: ClosedRange<Int>?
    let fan: ACFan?
    let features: ACFeatures
    var targetStep = 1
    var targetModes: Set<ClimateMode> = [.cool]
    var powerWritable = true
    var usesDeviceOptions = false
    var fanOptionsByMode: [ClimateMode: [FanSpeed]] = [:]

    var isTemperatureMode: Bool { mode.map { targetModes.contains($0) } ?? false }

    var canAdjust: Bool {
        isOn && isTemperatureMode && target.map { permitsTarget($0) } == true
    }

    func permitsTarget(_ target: Int) -> Bool {
        guard let limits, limits.contains(target), targetStep > 0 else { return false }
        return (target - limits.lowerBound).isMultiple(of: targetStep)
    }

    // Integer half-degrees keep target steps exact.
    func adjusted(by delta: Int, from draft: Int? = nil) -> Int? {
        guard canAdjust, let current = draft ?? target, let limits else { return nil }
        let next = current + delta * targetStep
        return limits.contains(next) ? next : nil
    }

    static func degrees(_ value: Int) -> String {
        (Double(value) / 2).formatted(.number.precision(.fractionLength(0...1)))
    }
}

struct RoomConditions: Sendable {
    let temperature: Int?
    let humidity: Int?

    var hasReading: Bool { temperature != nil || humidity != nil }
}

enum ClimateMode: String, CaseIterable, Codable, Sendable {
    case cool = "Cool"
    case fan = "Fan"
    case dry = "Dry"
    case heat = "Heat"
    case auto = "Auto"
    case humidify = "Humidify"

    static let selectable: [Self] = [.cool, .fan, .dry]
    var label: String { rawValue }
}

enum FanSpeed: String, CaseIterable, Codable, Sendable {
    case auto = "Auto"
    case silent = "Silent"
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"

    static let daikin: [Self] = [.auto, .silent, .one, .two, .three, .four, .five]
    var label: String { rawValue }
}

struct ACFan: Sendable {
    let selected: FanSpeed?
    let available: [FanSpeed]
}

enum SpecialOperation: String, CaseIterable, Sendable {
    case off = "Off"
    case boost = "Boost"
    case econo = "Econo"
}

struct ACFeatures: Sendable {
    let boost: Bool?
    let econo: Bool?
    let streamer: Bool?

    var specialOperation: SpecialOperation? {
        if boost == true { return .boost }
        if econo == true { return .econo }
        return boost != nil || econo != nil ? .off : nil
    }

    func supports(_ operation: SpecialOperation) -> Bool {
        switch operation {
        case .off: specialOperation != nil
        case .boost: boost != nil
        case .econo: econo != nil
        }
    }

    func confirms(_ operation: SpecialOperation) -> Bool {
        supports(operation) &&
            (boost == true) == (operation == .boost) &&
            (econo == true) == (operation == .econo)
    }
}

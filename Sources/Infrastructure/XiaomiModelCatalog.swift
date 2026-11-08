import Foundation

struct XiaomiModelCatalog {
    func profile(for model: String, deviceID: UInt64) async throws -> XiaomiProfile {
        let catalog: Catalog = try await fetch(path: "instances", query: URLQueryItem(name: "status", value: "all"))
        let models = catalog.instances.filter { $0.model == model && $0.status == "released" }
        guard let entry = models.max(by: { ($0.version ?? 0) < ($1.version ?? 0) }),
              entry.type.hasPrefix("urn:miot-spec-v2:device:air-conditioner:") else {
            throw XiaomiError.incompatible
        }

        let spec: Specification = try await fetch(path: "instance", query: URLQueryItem(name: "type", value: entry.type))
        guard spec.type == entry.type,
              let air = spec.service("air-conditioner"), let power = air.find("on"), power.format == "bool" else {
            throw XiaomiError.incompatible
        }
        let fan = spec.service("fan-control")
        let environment = spec.service("environment")
        let mode = air.find("mode")
        let speed = fan?.find("fan-level")
        let target = air.find("target-temperature").flatMap { celsius($0) ? $0 : nil }
        let room = environment?.find("temperature").flatMap { celsius($0) ? $0 : nil }
        let humidity = environment?.find("relative-humidity")
        let eco = air.find("eco").flatMap { $0.format == "bool" && $0.access.contains("write") ? $0 : nil }

        return XiaomiProfile(
            model: model, deviceID: deviceID, power: air.reference(power),
            mode: mode.map(air.reference),
            modes: choices(mode?.values, identify: climateMode),
            setpoint: target.map { setpoint($0, in: air) },
            fan: fan.flatMap { service in speed.map(service.reference) },
            speeds: choices(speed?.values, identify: fanSpeed),
            roomTemperature: environment.flatMap { service in room.map(service.reference) },
            roomHumidity: environment.flatMap { service in humidity.map(service.reference) },
            eco: eco.map(air.reference)
        )
    }

    private func fetch<T: Decodable>(path: String, query: URLQueryItem) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "miot-spec.org"
        components.path = "/miot-spec-v2/" + path
        components.queryItems = [query]
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(from: components.url!)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw XiaomiError.catalogUnavailable
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            try Task.checkCancellation()
            throw XiaomiError.catalogUnavailable
        }
    }

    private func setpoint(_ property: Property, in service: Service) -> XiaomiProfile.Setpoint {
        let limits: ClosedRange<Int>?
        let step: Int
        if let range = property.range, range.count == 3,
           let low = halfDegrees(range[0]), let high = halfDegrees(range[1]),
           let increment = halfDegrees(range[2]),
           (0...100).contains(low), (low...100).contains(high), (1...20).contains(increment) {
            limits = low...high
            step = increment
        } else {
            limits = nil
            step = 1
        }
        return XiaomiProfile.Setpoint(property: service.reference(property), limits: limits, step: step)
    }

    private func halfDegrees(_ value: Double) -> Int? {
        Int(exactly: value * 2)
    }

    private func celsius(_ property: Property) -> Bool {
        property.unit == nil || property.unit == "celsius"
    }

    private func choices<T: Hashable>(_ values: [Choice]?, identify: (String) -> T?) -> [T: Int] {
        var results: [T: Int] = [:]
        var ambiguous: Set<T> = []
        for choice in values ?? [] {
            guard let value = choice.value,
                  let option = [choice.name, choice.description].compactMap({ $0 }).compactMap(identify).first else {
                continue
            }
            if let previous = results[option], previous != value { ambiguous.insert(option) }
            results[option] = value
        }
        return results.filter { !ambiguous.contains($0.key) }
    }

    private func climateMode(_ label: String) -> ClimateMode? {
        switch normalized(label) {
        case "cool", "cooling", "制冷": .cool
        case "dry", "dehumidify", "dehumidification", "除湿": .dry
        case "fan", "fanonly", "ventilation", "风扇", "送风": .fan
        case "heat", "heating", "制热": .heat
        case "auto", "automatic", "自动": .auto
        case "humidify", "加湿": .humidify
        default: nil
        }
    }

    private func fanSpeed(_ label: String) -> FanSpeed? {
        switch normalized(label) {
        case "auto", "automatic", "自动": .auto
        case "silent", "quiet", "静音": .silent
        case "1", "level1", "low", "一档", "1档": .one
        case "2", "level2", "medium", "二档", "2档": .two
        case "3", "level3", "high", "三档", "3档": .three
        case "4", "level4", "四档", "4档": .four
        case "5", "level5", "五档", "5档": .five
        case "6", "level6", "六档", "6档": .six
        case "7", "level7", "七档", "7档": .seven
        default: nil
        }
    }

    private func normalized(_ label: String) -> String {
        String(label.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            let model: String
            let type: String
            let status: String
            let version: Int?
        }

        let instances: [Entry]
    }

    private struct Specification: Decodable {
        let type: String
        let services: [Service]

        func service(_ name: String) -> Service? {
            services.first { $0.type.hasPrefix("urn:miot-spec-v2:service:" + name + ":") }
        }
    }

    private struct Service: Decodable {
        let iid: Int
        let type: String
        let properties: [Property]?

        func find(_ name: String) -> Property? {
            properties?.first {
                $0.type.hasPrefix("urn:miot-spec-v2:property:" + name + ":") && $0.access.contains("read")
            }
        }

        func reference(_ property: Property) -> XiaomiProfile.Property {
            XiaomiProfile.Property(service: iid, property: property.iid, writable: property.access.contains("write"))
        }
    }

    private struct Property: Decodable {
        let iid: Int
        let type: String
        let format: String
        let access: [String]
        let unit: String?
        let range: [Double]?
        let values: [Choice]?

        enum CodingKeys: String, CodingKey {
            case iid, type, format, access, unit
            case range = "value-range"
            case values = "value-list"
        }
    }

    private struct Choice: Decodable {
        let name: String?
        let description: String?
        let value: Int?

        enum CodingKeys: CodingKey { case name, description, value }

        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            name = try? fields.decode(String.self, forKey: .name)
            description = try? fields.decode(String.self, forKey: .description)
            value = try? fields.decode(Int.self, forKey: .value)
        }
    }
}

import Foundation

struct DaikinClient: ACDevice {
    private static let indoor = "/dsiot/edge/adr_0100.dgc_status"
    private static let outdoor = "/dsiot/edge/adr_0200.dgc_status"
    let address: LocalAddress
    var requests = DaikinRequestProvider.shared

    func readStatus() async throws -> ACStatus {
        let replies = try await exchange([
            Command(op: 2, to: Self.indoor), Command(op: 2, to: Self.outdoor)
        ])
        guard let reply = replies.first, reply.rsc == 2000, reply.pc?.pn == "dgc_status",
              let unit = reply.pc?.child("e_1002"),
              let settings = unit.child("e_3001"),
              let modeNode = settings.child("p_01"), let wireMode = modeNode.pv?.uppercased(),
              let power = unit.child("e_A002")?.child("p_01")?.pv,
              power == "00" || power == "01" else {
            throw ACDeviceError.unexpectedResponse
        }

        let targetNode = settings.child("p_02")
        let limits: ClosedRange<Int>?
        if let min = decodeByte(targetNode?.md?.mi), let max = decodeByte(targetNode?.md?.mx),
           (20...80).contains(min), (min...80).contains(max) {
            limits = min...max
        } else {
            limits = nil
        }

        let target = decodeByte(targetNode?.pv).flatMap { (20...80).contains($0) ? $0 : nil }
        let sensors = unit.child("e_A00B")
        let room = RoomConditions(
            temperature: decodeByte(sensors?.child("p_01")?.pv).flatMap { (0...60).contains($0) ? $0 : nil },
            humidity: decodeByte(sensors?.child("p_02")?.pv).flatMap { (0...100).contains($0) ? $0 : nil }
        )
        let mode = ClimateMode.allCases.first { $0.wireValue == wireMode }
        let modeMask = modeNode.allowedValueMask ?? UInt16.max
        let availableModes = ClimateMode.selectable.filter { modeMask & (1 << $0.wireCode) != 0 }
        let outside = replies.dropFirst().first
        let indoorOptions = unit.child("e_3003")
        let features = ACFeatures(
            boost: outside?.rsc == 2000
                ? outside?.pc?.child("e_1003")?.child("e_3002")?.child("p_44")?.flag : nil,
            econo: indoorOptions?.child("p_24")?.flag,
            streamer: indoorOptions?.child("p_20")?.flag
        )

        return ACStatus(
            isOn: power == "01", mode: mode, availableModes: availableModes, room: room, target: target,
            limits: limits, fan: readFan(mode: mode, settings: settings), features: features
        )
    }

    func write(_ change: ACChange, current: ACStatus) async throws {
        switch change {
        case let .target(target, _, _):
            try await setCoolingTarget(target)
        case let .power(isOn):
            try await setPower(isOn)
        case let .mode(mode):
            try await setMode(mode)
        case let .fan(speed, mode):
            guard let parameter = mode.fanParameter, let value = speed.daikinWireValue else {
                throw ACDeviceError.unexpectedResponse
            }
            try await setFanSpeed(value, parameter: parameter)
        case let .special(operation):
            try await setSpecialOperation(operation, current: current.features)
        case let .streamer(isOn):
            try await setStreamer(isOn)
        }
    }

    private func setCoolingTarget(_ target: Int) async throws {
        let target = WriteNode("p_02", value: String(format: "%02X", target))
        try await write([WriteNode("e_3001", children: [target])])
    }

    private func setPower(_ isOn: Bool) async throws {
        // Use the remote's operation marker so a normal stop preserves the unit's cleaning behavior.
        try await write([
            operationMarker(isOn ? "00" : "01"),
            WriteNode("e_A002", children: [WriteNode("p_01", value: isOn ? "01" : "00")]),
        ])
    }

    private func setMode(_ mode: ClimateMode) async throws {
        try await setOperatingSetting(WriteNode("p_01", value: mode.wireValue))
    }

    private func setFanSpeed(_ value: String, parameter: String) async throws {
        try await setOperatingSetting(WriteNode(parameter, value: value))
    }

    private func setSpecialOperation(_ operation: SpecialOperation, current: ACFeatures) async throws {
        var commands: [Command] = []
        let wantsBoost = operation == .boost
        let wantsEcono = operation == .econo
        if let boost = current.boost, boost != wantsBoost {
            let setting = WriteNode("e_3002", children: [WriteNode("p_44", value: wantsBoost ? "01" : "00")])
            commands.append(update([setting], outdoor: true))
        }
        if let econo = current.econo, econo != wantsEcono {
            let setting = WriteNode("e_3003", children: [WriteNode("p_24", value: wantsEcono ? "01" : "00")])
            commands.append(update([setting]))
        }
        // Clear the old mode before enabling the new one.
        if wantsBoost { commands.reverse() }
        try await sendUpdates(commands)
    }

    private func setStreamer(_ isOn: Bool) async throws {
        try await write([
            WriteNode("e_3003", children: [WriteNode("p_20", value: isOn ? "01" : "00")])
        ])
    }

    private func setOperatingSetting(_ property: WriteNode) async throws {
        try await write([
            operationMarker("02"),
            WriteNode("e_3001", children: [property]),
        ])
    }

    private func readFan(mode: ClimateMode?, settings: ReadNode) -> ACFan? {
        guard let parameter = mode?.fanParameter, let node = settings.child(parameter) else { return nil }
        let speeds = FanSpeed.daikin
        let selected = speeds.first { $0.daikinWireValue == node.pv?.uppercased() }
        let available: [FanSpeed]
        if let mask = node.allowedValueMask {
            available = speeds.filter { speed in
                speed.daikinWireCode.map { mask & (1 << $0) != 0 } ?? false
            }
        } else {
            available = selected == nil ? [] : speeds
        }
        return ACFan(selected: selected, available: available)
    }

    private func operationMarker(_ value: String) -> WriteNode {
        WriteNode("e_3003", children: [WriteNode("p_2D", value: value)])
    }

    private func write(_ properties: [WriteNode]) async throws {
        try await sendUpdates([update(properties)])
    }

    private func update(_ properties: [WriteNode], outdoor: Bool = false) -> Command {
        let payload = WriteNode("dgc_status", children: [
            WriteNode(outdoor ? "e_1003" : "e_1002", children: properties)
        ])
        return Command(op: 3, to: outdoor ? Self.outdoor : Self.indoor, pc: payload)
    }

    private func sendUpdates(_ commands: [Command]) async throws {
        guard !commands.isEmpty else { return }
        let replies = try await exchange(commands)
        guard replies.count == commands.count,
              replies.allSatisfy({ $0.rsc == 2000 || $0.rsc == 2004 }) else {
            throw ACDeviceError.unconfirmed
        }
    }

    private func exchange(_ commands: [Command]) async throws -> [Reply] {
        // LocalAddress accepts canonical private IPv4 addresses only.
        let url = URL(string: "http://\(address.value)/dsiot/multireq")!
        let body = try JSONEncoder().encode(Envelope(requests: commands))
        let data = try await requests.post(to: url, body: body)
        guard let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: data),
              !envelope.responses.isEmpty, envelope.responses.count <= commands.count else {
            throw ACDeviceError.unexpectedResponse
        }
        return envelope.responses
    }

    private func decodeByte(_ raw: String?) -> Int? {
        guard let raw, raw.utf8.count == 2, let number = UInt8(raw, radix: 16) else { return nil }
        return Int(number)
    }
}

private extension ClimateMode {
    var wireCode: UInt8 {
        switch self {
        case .fan: 0x00
        case .heat: 0x01
        case .cool: 0x02
        case .auto: 0x03
        case .dry: 0x05
        case .humidify: 0x08
        }
    }

    var wireValue: String { String(format: "%02X00", wireCode) }

    var fanParameter: String? {
        switch self {
        case .fan: "p_28"
        case .heat: "p_0A"
        case .cool: "p_09"
        case .auto: "p_26"
        case .dry: "p_27"
        case .humidify: nil
        }
    }
}

private extension FanSpeed {
    var daikinWireCode: UInt8? {
        switch self {
        case .auto: 0x0A
        case .silent: 0x0B
        case .one: 0x03
        case .two: 0x04
        case .three: 0x05
        case .four: 0x06
        case .five: 0x07
        case .six, .seven: nil
        }
    }

    var daikinWireValue: String? { daikinWireCode.map { String(format: "%02X00", $0) } }
}

private struct Envelope: Encodable {
    let requests: [Command]
}

private struct Command: Encodable {
    let op: Int
    let to: String
    var pc: WriteNode? = nil
}

private struct WriteNode: Encodable {
    let pn: String
    var pv: String?
    var pch: [WriteNode]?

    init(_ name: String, value: String? = nil, children: [WriteNode]? = nil) {
        pn = name
        pv = value
        pch = children
    }
}

private struct ResponseEnvelope: Decodable {
    let responses: [Reply]
}

private struct Reply: Decodable {
    let rsc: Int
    let pc: ReadNode?
}

private struct ReadNode: Decodable {
    struct Limits: Decodable {
        let mi: String?
        let mx: String?
    }

    let pn: String?
    let pv: String?
    let md: Limits?
    let pch: [ReadNode]?

    private enum CodingKeys: String, CodingKey { case pn, pv, md, pch }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        pn = try? fields.decode(String.self, forKey: .pn)
        pv = try? fields.decode(String.self, forKey: .pv)
        md = try? fields.decode(Limits.self, forKey: .md)
        pch = try? fields.decode([ReadNode].self, forKey: .pch)
    }

    func child(_ name: String) -> ReadNode? {
        pch?.first { $0.pn == name }
    }

    var flag: Bool? {
        switch pv {
        case "00": false
        case "01": true
        default: nil
        }
    }

    var allowedValueMask: UInt16? {
        // Mode and fan masks list allowed first-byte values in little-endian order.
        guard let raw = md?.mx, raw.utf8.count == 4 else { return nil }
        return UInt16(raw, radix: 16)?.byteSwapped
    }
}

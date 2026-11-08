import CommonCrypto
import CryptoKit
import Foundation
import Network

struct XiaomiRequestProvider: Sendable {
    struct Reply<Value: Decodable & Sendable>: Decodable, Sendable {
        let id: Int
        let result: Value?
    }

    let address: LocalAddress
    let token: XiaomiToken

    func request<Parameters: Encodable & Sendable, Result: Decodable & Sendable>(
        _ method: String,
        parameters: @escaping @Sendable (UInt64) -> Parameters,
        deviceID: UInt64? = nil
    ) async throws -> (UInt64, Result) {
        try await withThrowingTaskGroup(of: (UInt64, Result).self) { group in
            group.addTask {
                let session = XiaomiUDPSession(address: address)
                defer { session.close() }

                var messages = session.messages.makeAsyncIterator()
                session.send(XiaomiPacket.hello)
                guard let greeting = try await messages.next() else { throw CancellationError() }
                let header = try XiaomiPacket.header(from: greeting)
                guard greeting.count == 32, deviceID == nil || deviceID == header.deviceID else {
                    throw XiaomiError.authentication
                }

                let id = Int.random(in: 1...1_000_000_000)
                let request = RPC(id: id, method: method, params: parameters(header.deviceID))
                let payload = try JSONEncoder().encode(request)
                let codec = XiaomiPacket(token: token)
                session.send(try codec.encode(payload, header: header))

                while let packet = try await messages.next() {
                    if packet.count == 32 { continue }
                    let plaintext = try codec.decode(packet, deviceID: header.deviceID)
                    guard let reply = try? JSONDecoder().decode(Reply<Result>.self, from: plaintext) else {
                        throw XiaomiError.incompatible
                    }
                    guard reply.id == id else { continue }
                    guard let result = reply.result else { throw XiaomiError.incompatible }
                    return (header.deviceID, result)
                }
                throw CancellationError()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw XiaomiError.noReply
            }
            defer { group.cancelAll() }
            guard let reply = try await group.next() else { throw CancellationError() }
            return reply
        }
    }

    private struct RPC<Parameters: Encodable>: Encodable {
        let id: Int
        let method: String
        let params: Parameters
    }
}

private struct XiaomiUDPSession {
    let messages: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let connection: NWConnection

    init(address: LocalAddress) {
        let stream = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingNewest(8))
        messages = stream.stream
        continuation = stream.continuation
        connection = NWConnection(host: NWEndpoint.Host(address.value), port: 54321, using: .udp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed: stream.continuation.finish(throwing: XiaomiError.noReply)
            case .cancelled: stream.continuation.finish()
            default: break
            }
        }
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        Self.receive(connection, into: stream.continuation)
    }

    func send(_ packet: Data) {
        let continuation = self.continuation
        connection.send(content: packet, completion: .contentProcessed { error in
            if error != nil { continuation.finish(throwing: XiaomiError.noReply) }
        })
    }

    func close() {
        connection.cancel()
        continuation.finish()
    }

    private static func receive(
        _ connection: NWConnection,
        into continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) {
        connection.receiveMessage { data, _, _, error in
            if error != nil {
                continuation.finish(throwing: XiaomiError.noReply)
                return
            }
            guard let data, !data.isEmpty else {
                continuation.finish(throwing: XiaomiError.noReply)
                return
            }
            continuation.yield(data)
            receive(connection, into: continuation)
        }
    }
}

// miIO uses a 32-byte header and token-derived AES-128-CBC.
private struct XiaomiPacket {
    struct Header {
        let deviceID: UInt64
        let timestamp: UInt32
    }

    static let hello = Data([0x21, 0x31, 0, 32] + Array(repeating: 0xFF, count: 28))
    let token: XiaomiToken

    static func header(from packet: Data) throws -> Header {
        guard packet.count >= 32, packet.prefix(2).elementsEqual([0x21, 0x31]),
              Int(integer(packet.dropFirst(2).prefix(2))) == packet.count else {
            throw XiaomiError.incompatible
        }
        return Header(
            deviceID: integer(packet.dropFirst(4).prefix(8)),
            timestamp: UInt32(integer(packet.dropFirst(12).prefix(4)))
        )
    }

    func encode(_ plaintext: Data, header: Header) throws -> Data {
        let encrypted = try crypt(plaintext, operation: kCCEncrypt)
        var prefix = Data([0x21, 0x31])
        append(UInt16(32 + encrypted.count), to: &prefix)
        append(header.deviceID, to: &prefix)
        append(header.timestamp &+ 1, to: &prefix)
        return prefix + digest(prefix + token.bytes + encrypted) + encrypted
    }

    func decode(_ packet: Data, deviceID: UInt64) throws -> Data {
        let header = try Self.header(from: packet)
        let encrypted = Data(packet.dropFirst(32))
        guard header.deviceID == deviceID,
              digest(Data(packet.prefix(16)) + token.bytes + encrypted)
                .elementsEqual(packet.dropFirst(16).prefix(16)) else {
            throw XiaomiError.authentication
        }
        let plaintext = try crypt(encrypted, operation: kCCDecrypt)
        return Data(plaintext.prefix { $0 != 0 })
    }

    private func crypt(_ input: Data, operation: Int) throws -> Data {
        let key = digest(token.bytes)
        let iv = digest(key + token.bytes)
        let capacity = input.count + kCCBlockSizeAES128
        var output = Data(count: capacity)
        var written = 0
        let result = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                input.withUnsafeBytes { inputBytes in
                    output.withUnsafeMutableBytes { outputBytes in
                        CCCrypt(CCOperation(operation), CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding), keyBytes.baseAddress, key.count,
                                ivBytes.baseAddress, inputBytes.baseAddress, input.count,
                                outputBytes.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard result == kCCSuccess else { throw XiaomiError.authentication }
        return output.prefix(written)
    }

    private func digest(_ bytes: Data) -> Data {
        Data(Insecure.MD5.hash(data: bytes))
    }

    private static func integer(_ bytes: Data.SubSequence) -> UInt64 {
        bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    private func append<T: FixedWidthInteger>(_ number: T, to bytes: inout Data) {
        withUnsafeBytes(of: number.bigEndian) { bytes.append(contentsOf: $0) }
    }
}

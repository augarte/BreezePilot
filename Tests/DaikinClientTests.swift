import Foundation
import Testing
@testable import BreezePilot

struct DaikinClientTests {
    @Test func decodesStatusAndAvailableControls() async throws {
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        let address = try #require(LocalAddress("10.20.30.40"))
        let device = DaikinClient(address: address, requests: DaikinRequestProvider(session: session))

        let status = try await device.readStatus()

        #expect(status.isOn)
        #expect(status.mode == .cool)
        #expect(status.availableModes == [.cool, .dry])
        #expect(status.target == 53)
        #expect(status.limits == 36...64)
        #expect(status.room.temperature == 56)
        #expect(status.room.humidity == 60)
        #expect(status.fan?.selected == .silent)
        #expect(status.fan?.available == [.auto, .silent])
        #expect(status.features.specialOperation == .boost)
        #expect(status.features.streamer == true)
    }

    @Test(arguments: ["10.20.30.41", "10.20.30.42"])
    func rejectsInvalidStatusAndNonSuccessHTTPResponses(addressValue: String) async throws {
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        let address = try #require(LocalAddress(addressValue))
        let device = DaikinClient(address: address, requests: DaikinRequestProvider(session: session))

        await #expect(throws: ACDeviceError.unexpectedResponse) {
            try await device.readStatus()
        }
    }

    private func fixtureSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DaikinFixtureProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class DaikinFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, url.path == "/dsiot/multireq", request.httpMethod == "POST",
              request.value(forHTTPHeaderField: "Content-Type") == "application/json" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let status: Int
        let body: String
        switch url.host {
        case "10.20.30.40":
            status = 200
            body = Self.statusFixture
        case "10.20.30.41":
            status = 200
            body = #"{"responses":[{"rsc":2000,"pc":{"pn":"dgc_status"}}]}"#
        case "10.20.30.42":
            status = 404
            body = Self.statusFixture
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        guard let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static let statusFixture = """
    {
      "responses": [
        {"rsc": 2000, "pc": {"pn": "dgc_status", "pch": [
          {"pn": "e_1002", "pch": [
            {"pn": "e_A002", "pch": [{"pn": "p_01", "pv": "01"}]},
            {"pn": "e_3001", "pch": [
              {"pn": "p_01", "pv": "0200", "md": {"mx": "2400"}},
              {"pn": "p_02", "pv": "35", "md": {"mi": "24", "mx": "40"}},
              {"pn": "p_09", "pv": "0B00", "md": {"mx": "000C"}}
            ]},
            {"pn": "e_A00B", "pch": [{"pn": "p_01", "pv": "38"}, {"pn": "p_02", "pv": "3C"}]},
            {"pn": "e_3003", "pch": [{"pn": "p_24", "pv": "00"}, {"pn": "p_20", "pv": "01"}]}
          ]}
        ]}},
        {"rsc": 2000, "pc": {"pn": "dgc_status", "pch": [
          {"pn": "e_1003", "pch": [{"pn": "e_3002", "pch": [{"pn": "p_44", "pv": "01"}]}]}
        ]}}
      ]
    }
    """
}

import Foundation
import Testing
@testable import BreezePilot

struct ConnectionInputTests {
    @Test func trimsAndAcceptsPrivateIPv4Addresses() {
        #expect(LocalAddress(" 10.20.30.40\n")?.value == "10.20.30.40")
        #expect(LocalAddress("172.16.0.1") != nil)
        #expect(LocalAddress("172.31.255.254") != nil)
        #expect(LocalAddress("192.168.20.30") != nil)
    }

    @Test func rejectsNonlocalAndMalformedAddresses() {
        for address in [
            "172.15.0.1", "172.32.0.1", "127.0.0.1", "169.254.0.1", "169.254.255.1", "203.0.113.42",
            "192.168.01.42", "10.20.30.256", "10.20.30", "10..30.40",
            "10.20.30.40:80", "http://10.20.30.40", "ac.local", "fd00::1",
        ] {
            #expect(LocalAddress(address) == nil)
        }
    }

    @Test func acceptsIPv4LinkLocalAddresses() {
        #expect(LocalAddress("169.254.1.0") != nil)
        #expect(LocalAddress("169.254.254.255") != nil)
    }

    @Test func restrictsPlainHTTPExceptionsToLocalIPv4Ranges() throws {
        let ats = try #require(Bundle.main.infoDictionary?["NSAppTransportSecurity"] as? [String: Any])
        let exceptions = try #require(ats["NSExceptionDomains"] as? [String: [String: Bool]])
        #expect(ats["NSAllowsArbitraryLoads"] as? Bool != true)
        #expect(Set(exceptions.keys) == ["10.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16"])
        #expect(exceptions.values.allSatisfy { $0["NSExceptionAllowsInsecureHTTPLoads"] == true })
    }

    @Test func decodesTrimmedMixedCaseHexTokens() {
        let token = XiaomiToken(" 00112233445566778899aAbBcCdDeEfF\n")
        #expect(token?.bytes == Data((0...15).map { UInt8($0 * 17) }))
    }

    @Test func rejectsWrongTokenLengthsAndNonHexCharacters() {
        #expect(XiaomiToken(String(repeating: "a", count: 31)) == nil)
        #expect(XiaomiToken(String(repeating: "a", count: 33)) == nil)
        #expect(XiaomiToken(String(repeating: "g", count: 32)) == nil)
        #expect(XiaomiToken("0011223344556677 899aabbccddeeff") == nil)
        #expect(XiaomiToken(bytes: Data(count: 15)) == nil)
        #expect(XiaomiToken(bytes: Data(count: 16)) != nil)
    }
}

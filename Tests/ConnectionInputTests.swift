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
            "172.15.0.1", "172.32.0.1", "127.0.0.1", "169.254.1.1", "203.0.113.42",
            "192.168.01.42", "10.20.30.256", "10.20.30", "10..30.40",
            "10.20.30.40:80", "http://10.20.30.40", "ac.local", "fd00::1",
        ] {
            #expect(LocalAddress(address) == nil)
        }
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

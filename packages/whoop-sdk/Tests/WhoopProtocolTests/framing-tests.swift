import XCTest
@testable import WhoopProtocol

final class WhoopFramingTests: XCTestCase {
    func testCRC8KnownValue() {
        XCTAssertEqual(whoopCRC8([0x08, 0x00]), 0x6E)
    }

    func testCRC32Empty() {
        XCTAssertEqual(whoopCRC32([]), 0x0000_0000)
    }

    func testWhoop4FrameRoundTrip() {
        let frame = WhoopCommand.getBatteryLevel.frame4(seq: 1)
        let check = verifyWhoopFrame4(frame)
        XCTAssertTrue(check.ok)
        XCTAssertNotNil(check.declaredLength)
    }

    func testWhoop5ClientHelloValidates() {
        let hello = WhoopDeviceFamily.whoop5.clientHello!
        let check = verifyWhoopFrame5(hello)
        XCTAssertTrue(check.ok)
    }

    func testReassemblerSingleFrame() {
        let frame = WhoopCommand.setClock.frame4(seq: 2, payload: WhoopCommand.setClockPayload())
        var reassembler = WhoopReassembler(family: .whoop4)
        let result = reassembler.feed(frame)
        XCTAssertEqual(result.frames.count, 1)
        XCTAssertEqual(result.crcFailures, 0)
    }

    func testPuffinTypeCanonicalization() {
        XCTAssertEqual(WhoopPacketType.canonical(38), .commandResponse)
        XCTAssertEqual(WhoopPacketType.canonical(56), .metadata)
        XCTAssertEqual(WhoopPacketType.canonical(40), .realtimeData)
    }

    func testStandardHeartRateParser() {
        let data: [UInt8] = [0x00, 72]
        let parsed = StandardHeartRate.parse(data)
        XCTAssertEqual(parsed?.hr, 72)
        XCTAssertTrue(parsed?.rr.isEmpty ?? false)
    }
}

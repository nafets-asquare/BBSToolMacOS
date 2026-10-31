import Testing
@testable import BafangProtocol

/// Settings matching what the original tool would send for a typical BBS02 profile.
/// Expected bytes were computed independently from the Delphi `WriteDev` logic.
enum Fixtures {
    static let basic = BasicSettings(
        lowBatteryProtection: 41,
        currentLimit: 18,
        assistCurrentLimit: Array(stride(from: 10, through: 100, by: 10)),
        assistSpeedLimit: Array(stride(from: 10, through: 100, by: 10)),
        wheelDiameter: .inches(26),
        speedMeterType: .wheelMeter,
        speedMeterSignals: 1
    )
    static let basicPacket: [UInt8] = [
        0x16, 0x52, 0x18, 0x29, 0x12,
        0x0A, 0x14, 0x1E, 0x28, 0x32, 0x3C, 0x46, 0x50, 0x5A, 0x64,
        0x0A, 0x14, 0x1E, 0x28, 0x32, 0x3C, 0x46, 0x50, 0x5A, 0x64,
        0x34, 0x01, 0x26,
    ]

    static let pedalAssist = PedalAssistSettings(
        pedalSensorType: .doubleSignal24,
        designatedAssistLevel: nil,
        speedLimit: 25,
        startCurrent: 20,
        slowStartMode: 5,
        startDegree: 20,
        workMode: 10,
        stopDelay: 8,
        currentDecay: 20,
        stopDecay: 8,
        keepCurrent: 20
    )
    static let pedalAssistPacket: [UInt8] = [
        0x16, 0x53, 0x0B, 0x03, 0xFF, 0x19, 0x14, 0x05, 0x14, 0x0A, 0x08, 0x14, 0x08, 0x14, 0xE8,
    ]

    static let throttle = ThrottleSettings(
        startVoltage: 11,
        endVoltage: 35,
        mode: .speed,
        designatedAssistLevel: 3,
        speedLimit: nil,
        startCurrent: 20
    )
    static let throttlePacket: [UInt8] = [0x16, 0x54, 0x06, 0x0B, 0x23, 0x00, 0x03, 0xFF, 0x14, 0x9E]
}

@Suite struct PacketTests {
    @Test func connectMatchesOriginalTool() {
        #expect(Packet.connect == [0x11, 0x51, 0x04, 0xB0, 0x05])
    }

    @Test func readRequests() {
        #expect(Packet.read(.basic) == [0x11, 0x52])
        #expect(Packet.read(.pedalAssist) == [0x11, 0x53])
        #expect(Packet.read(.throttle) == [0x11, 0x54])
    }

    @Test func checksumWrapsModulo256() {
        #expect(Packet.checksum([0xFF, 0x02]) == 0x01)
        #expect(Packet.checksum([]) == 0)
    }

    @Test func writeBasic() throws {
        #expect(try Packet.write(Fixtures.basic) == Fixtures.basicPacket)
    }

    @Test func writePedalAssist() throws {
        #expect(try Packet.write(Fixtures.pedalAssist) == Fixtures.pedalAssistPacket)
    }

    @Test func writeThrottle() throws {
        #expect(try Packet.write(Fixtures.throttle) == Fixtures.throttlePacket)
    }

    @Test func writeRejectsWrongPayloadLength() {
        #expect(throws: ProtocolError.wrongPayloadLength(.throttle, expected: 6, actual: 5)) {
            try Packet.write(.throttle, payload: [1, 2, 3, 4, 5])
        }
    }
}

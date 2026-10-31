import Testing
@testable import BafangProtocol

/// Responses captured from a BBSHD (firmware V1.0.0.4) with `bbstool read --trace`.
@Suite struct HardwareCaptureTests {
    static let general: [UInt8] = [
        0x51, 0x10, 0x53, 0x5A, 0x42, 0x46, 0x42, 0x42, 0x53, 0x33,
        0x31, 0x35, 0x31, 0x30, 0x30, 0x34, 0x02, 0x1C, 0xE9,
    ]
    static let basic: [UInt8] = [
        0x52, 0x18, 0x2A, 0x1C,
        0x01, 0x0A, 0x14, 0x1E, 0x28, 0x32, 0x41, 0x50, 0x5A, 0x64,
        0x01, 0x64, 0x64, 0x64, 0x64, 0x64, 0x64, 0x64, 0x64, 0x64,
        0x34, 0x01, 0x50,
    ]
    static let pedalAssist: [UInt8] = [0x53, 0x0B, 0x03, 0xFF, 0xFF, 0x02, 0x02, 0x03, 0xFF, 0x0F, 0x06, 0x04, 0x46, 0xC4]
    static let throttle: [UInt8] = [0x54, 0x06, 0x0B, 0x28, 0x00, 0x09, 0xFF, 0x02, 0x97]
    /// Reply to writing the throttle block back unchanged.
    static let throttleWriteAck: [UInt8] = [0x54, 0x06, 0x5A]

    @Test func throttleWriteAccepted() throws {
        var framer = ResponseFramer()
        framer.append(Self.throttleWriteAck)
        guard case .writeAck(.throttle, let code) = try framer.next(expecting: .writeAck(.throttle)) else {
            Issue.record("expected a write acknowledgement")
            return
        }
        #expect(ThrottleSettings.writeResult(code: code) == .accepted)
        #expect(framer.buffer.isEmpty)
    }

    private func frame(_ bytes: [UInt8], _ block: Block) throws -> DataResponse {
        var framer = ResponseFramer()
        framer.append(bytes)
        guard case .data(let response) = try framer.next(expecting: .data(block)) else {
            throw ProtocolError.wrongPayloadLength(block, expected: 0, actual: 0)
        }
        #expect(framer.buffer.isEmpty)
        #expect(response.checksumMatches)
        return response
    }

    @Test func general() throws {
        let info = try GeneralInfo(payload: frame(Self.general, .general).payload)
        #expect(info.manufacturer == "SZBF")
        #expect(info.model == "BBS3")
        #expect(info.hardwareVersion == "1.5")
        #expect(info.firmwareVersion == "1.0.0.4")
        #expect(info.nominalVoltage == .v48)
        #expect(info.maxCurrent == 28)
    }

    @Test func basicRoundTrips() throws {
        let response = try frame(Self.basic, .basic)
        let settings = try BasicSettings(payload: response.payload)
        #expect(settings.lowBatteryProtection == 42)
        #expect(settings.currentLimit == 28)
        #expect(settings.assistCurrentLimit == [1, 10, 20, 30, 40, 50, 65, 80, 90, 100])
        #expect(settings.assistSpeedLimit == [1] + Array(repeating: 100, count: 9))
        #expect(settings.wheelDiameter == .inches(26))
        #expect(settings.speedMeterType == .wheelMeter)
        #expect(settings.speedMeterSignals == 1)
        // Writing back unchanged settings must produce the controller's own bytes
        #expect(try Packet.write(settings) == [Opcode.write.rawValue] + Self.basic)
    }

    @Test func pedalAssistRoundTrips() throws {
        let response = try frame(Self.pedalAssist, .pedalAssist)
        let settings = try PedalAssistSettings(payload: response.payload)
        #expect(settings.pedalSensorType == .doubleSignal24)
        #expect(settings.designatedAssistLevel == nil)
        #expect(settings.speedLimit == nil)
        #expect(settings.workMode == nil)
        #expect(settings.stopDelay == 15)
        #expect(settings.keepCurrent == 70)
        #expect(try Packet.write(settings) == [Opcode.write.rawValue] + Self.pedalAssist)
    }

    @Test func throttleRoundTrips() throws {
        let response = try frame(Self.throttle, .throttle)
        let settings = try ThrottleSettings(payload: response.payload)
        #expect(settings.startVoltage == 11)
        #expect(settings.endVoltage == 40)
        #expect(settings.mode == .speed)
        #expect(settings.designatedAssistLevel == 9)
        #expect(settings.speedLimit == nil)
        #expect(try Packet.write(settings) == [Opcode.write.rawValue] + Self.throttle)
    }
}

import Testing
@testable import BafangProtocol

/// Strips opcode, block, length and checksum from a write packet.
private func payload(of packet: [UInt8]) -> [UInt8] {
    Array(packet[3..<(packet.count - 1)])
}

@Suite struct BasicSettingsTests {
    @Test func decodesPayload() throws {
        #expect(try BasicSettings(payload: payload(of: Fixtures.basicPacket)) == Fixtures.basic)
    }

    @Test(arguments: WheelDiameter.standardChoices)
    func wheelDiameterRoundTrips(_ wheel: WheelDiameter) throws {
        var settings = Fixtures.basic
        settings.wheelDiameter = wheel
        #expect(try BasicSettings(payload: settings.encoded()).wheelDiameter == wheel)
    }

    @Test func wheelDiameterCodes() {
        #expect(WheelDiameter.c700.code == 55)
        #expect(WheelDiameter.inches(29).code == 58)
        #expect(WheelDiameter.standardChoices.map(\.label) == [
            "16\"", "17\"", "18\"", "19\"", "20\"", "21\"", "22\"", "23\"", "24\"", "25\"", "26\"", "27\"",
            "700C", "28\"", "29\"", "30\"",
        ])
        #expect(WheelDiameter(code: 53).label == "26.5\"")
    }

    @Test func speedMeterByMotorPhaseUsesTypeThree() throws {
        var settings = Fixtures.basic
        settings.speedMeterType = .motorPhase
        settings.speedMeterSignals = 6
        let encoded = try settings.encoded()
        #expect(encoded[23] == 3 * 64 + 6)
        #expect(try BasicSettings(payload: encoded) == settings)
    }

    @Test func unknownSpeedMeterTypeThrows() {
        var bytes = payload(of: Fixtures.basicPacket)
        bytes[23] = 2 * 64 + 1
        #expect(throws: ProtocolError.unexpectedValue(field: "Speed Meter Type", value: 2)) {
            try BasicSettings(payload: bytes)
        }
    }

    @Test func encodeValidatesAssistLevels() {
        var settings = Fixtures.basic
        settings.assistSpeedLimit.removeLast()
        #expect(throws: ProtocolError.invalidValue(field: "Assist Speed Limit", value: 9)) {
            try settings.encoded()
        }
    }

    @Test func encodeValidatesSpeedMeterSignals() {
        var settings = Fixtures.basic
        settings.speedMeterSignals = 64
        #expect(throws: ProtocolError.invalidValue(field: "Speed Meter Signals", value: 64)) {
            try settings.encoded()
        }
    }

    @Test func decodeRejectsWrongLength() {
        #expect(throws: ProtocolError.wrongPayloadLength(.basic, expected: 24, actual: 23)) {
            try BasicSettings(payload: Array(repeating: 0, count: 23))
        }
    }
}

@Suite struct PedalAssistSettingsTests {
    @Test func decodesPayload() throws {
        #expect(try PedalAssistSettings(payload: payload(of: Fixtures.pedalAssistPacket)) == Fixtures.pedalAssist)
    }

    @Test func byDisplayIsEncodedAs0xFF() throws {
        var settings = Fixtures.pedalAssist
        settings.designatedAssistLevel = nil
        settings.speedLimit = nil
        settings.workMode = nil
        let encoded = try settings.encoded()
        #expect(encoded[1] == 0xFF)
        #expect(encoded[2] == 0xFF)
        #expect(encoded[6] == 0xFF)
        #expect(try PedalAssistSettings(payload: encoded) == settings)
    }

    @Test func explicit0xFFIsRejected() {
        var settings = Fixtures.pedalAssist
        settings.speedLimit = 0xFF
        #expect(throws: ProtocolError.invalidValue(field: "Speed Limit", value: 255)) {
            try settings.encoded()
        }
    }

    @Test func unknownPedalSensorTypeThrows() {
        var bytes = payload(of: Fixtures.pedalAssistPacket)
        bytes[0] = 4
        #expect(throws: ProtocolError.unexpectedValue(field: "Pedal Sensor Type", value: 4)) {
            try PedalAssistSettings(payload: bytes)
        }
    }
}

@Suite struct ThrottleSettingsTests {
    @Test func decodesPayload() throws {
        #expect(try ThrottleSettings(payload: payload(of: Fixtures.throttlePacket)) == Fixtures.throttle)
    }

    @Test func unknownModeThrows() {
        var bytes = payload(of: Fixtures.throttlePacket)
        bytes[2] = 2
        #expect(throws: ProtocolError.unexpectedValue(field: "Mode", value: 2)) {
            try ThrottleSettings(payload: bytes)
        }
    }
}

@Suite struct WriteResultTests {
    @Test func successCodeEqualsPayloadLength() {
        #expect(BasicSettings.writeResult(code: 24) == .accepted)
        #expect(PedalAssistSettings.writeResult(code: 11) == .accepted)
        #expect(ThrottleSettings.writeResult(code: 6) == .accepted)
    }

    @Test func errorCodeIsFieldIndex() {
        #expect(BasicSettings.writeResult(code: 0) == .rejected(fieldIndex: 0, fieldName: "Low Battery Protection"))
        #expect(BasicSettings.writeResult(code: 3) == .rejected(fieldIndex: 3, fieldName: "Assist 1 Current Limit"))
        #expect(BasicSettings.writeResult(code: 13) == .rejected(fieldIndex: 13, fieldName: "Assist 1 Speed Limit"))
        #expect(BasicSettings.writeResult(code: 23) == .rejected(fieldIndex: 23, fieldName: "Speed Meter"))
        #expect(PedalAssistSettings.writeResult(code: 10) == .rejected(fieldIndex: 10, fieldName: "Keep Current"))
        #expect(ThrottleSettings.writeResult(code: 5) == .rejected(fieldIndex: 5, fieldName: "Start Current"))
    }

    @Test func unknownCode() {
        #expect(ThrottleSettings.writeResult(code: 7) == .unknown(code: 7))
    }

    @Test func fieldNamesCoverPayload() {
        #expect(BasicSettings.fieldNames.count == 24)
        #expect(PedalAssistSettings.fieldNames.count == 11)
        #expect(ThrottleSettings.fieldNames.count == 6)
    }
}

@Suite struct GeneralInfoTests {
    static let payload: [UInt8] = Array("HZXTSZZ610".utf8) + Array("2001".utf8) + [4, 30]

    @Test func decodesPayload() throws {
        let info = try GeneralInfo(payload: Self.payload)
        #expect(info.manufacturer == "HZXT")
        #expect(info.model == "SZZ6")
        #expect(info.hardwareVersion == "1.0")
        #expect(info.firmwareVersion == "2.0.0.1")
        #expect(info.nominalVoltage == .v24to48)
        #expect(info.maxCurrent == 30)
    }

    @Test func trimsPaddingInNames() throws {
        var bytes = Self.payload
        bytes[6] = 0x20
        bytes[7] = 0x00
        #expect(try GeneralInfo(payload: bytes).model == "SZ")
    }

    @Test func rejectsShortPayload() {
        #expect(throws: ProtocolError.wrongPayloadLength(.general, expected: 16, actual: 15)) {
            try GeneralInfo(payload: Array(Self.payload.prefix(15)))
        }
    }

    @Test func nominalVoltageCodes() {
        #expect((0...6).map { NominalVoltage(code: $0) } == [.v24, .v36, .v48, .v60, .v24to48, .v24to60, .v24to60])
        #expect(NominalVoltage.v48.lowBatteryRange == 38...43)
        #expect(NominalVoltage.v24to60.lowBatteryRange == 18...55)
    }
}

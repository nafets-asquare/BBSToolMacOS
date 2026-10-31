import Foundation
import Testing
@testable import BafangProtocol

/// The profiles shipped with the original tool, as included in the app bundle.
private func shippedProfile(_ name: String) throws -> Data {
    let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Profiles")
    return try Data(contentsOf: resources.appendingPathComponent("\(name).el"))
}

@Suite struct ProfileTests {
    @Test func decodesPenoffProfile() throws {
        let settings = try Profile.decode(shippedProfile("Penoff"))

        #expect(settings.basic.lowBatteryProtection == 41)
        #expect(settings.basic.currentLimit == 25)
        #expect(settings.basic.assistCurrentLimit == [1, 50, 58, 64, 70, 76, 82, 88, 94, 100])
        #expect(settings.basic.assistSpeedLimit == [1, 38, 44, 52, 60, 68, 76, 84, 92, 100])
        #expect(settings.basic.wheelDiameter == .inches(26))       // WD=10
        #expect(settings.basic.speedMeterType == .wheelMeter)
        #expect(settings.basic.speedMeterSignals == 1)

        #expect(settings.pedalAssist.pedalSensorType == .doubleSignal24)
        #expect(settings.pedalAssist.designatedAssistLevel == nil)  // DA=0
        #expect(settings.pedalAssist.speedLimit == nil)             // SL=0
        #expect(settings.pedalAssist.slowStartMode == 4)            // SSM=3
        #expect(settings.pedalAssist.workMode == nil)               // WM=0
        #expect(settings.pedalAssist.startCurrent == 20)
        #expect(settings.pedalAssist.startDegree == 4)
        #expect(settings.pedalAssist.stopDelay == 25)
        #expect(settings.pedalAssist.currentDecay == 8)
        #expect(settings.pedalAssist.stopDecay == 0)
        #expect(settings.pedalAssist.keepCurrent == 60)

        #expect(settings.throttle.startVoltage == 11)
        #expect(settings.throttle.endVoltage == 42)
        #expect(settings.throttle.mode == .current)
        #expect(settings.throttle.designatedAssistLevel == 6)       // DA=7
        #expect(settings.throttle.speedLimit == 40)                 // SL=26
        #expect(settings.throttle.startCurrent == 10)
    }

    @Test func reencodingPenoffProfileReproducesTheFile() throws {
        let data = try shippedProfile("Penoff")
        #expect(Data(Profile.encode(try Profile.decode(data)).utf8) == data)
    }

    @Test func decodesDefaultProfileWithItsOwnKeyOrder() throws {
        let settings = try Profile.decode(shippedProfile("DefaultProfile"))
        #expect(settings.basic.wheelDiameter == .inches(17))        // WD=1
        #expect(settings.pedalAssist.slowStartMode == 6)            // SSM=5
        #expect(settings.pedalAssist.workMode == 10)                // WM=1
        #expect(settings.throttle.designatedAssistLevel == 3)       // DA=4
        #expect(settings.throttle.speedLimit == 17)                 // SL=3
    }

    @Test func roundTripsAllSpecialValues() throws {
        var settings = try Profile.decode(shippedProfile("Penoff"))
        settings.basic.wheelDiameter = .c700
        settings.basic.speedMeterType = .motorPhase
        settings.pedalAssist.designatedAssistLevel = 0
        settings.pedalAssist.speedLimit = 15
        settings.pedalAssist.workMode = 80
        settings.throttle.designatedAssistLevel = nil
        settings.throttle.speedLimit = nil
        #expect(try Profile.decode(Profile.encode(settings)) == settings)
    }

    @Test func wheelOutsideTheListIsKeptExactly() throws {
        var settings = try Profile.decode(shippedProfile("Penoff"))
        settings.basic.wheelDiameter = WheelDiameter(code: 53)  // 26.5"
        let text = Profile.encode(settings)
        #expect(text.contains("WD=10\r\nWDCODE=53\r\n"))  // nearest listed size for the original tool
        #expect(try Profile.decode(text).basic.wheelDiameter == WheelDiameter(code: 53))
    }

    @Test func toleratesUnixLineEndingsCaseAndWhitespace() throws {
        let text = "[basic]\nlbp = 42\n; comment\n[PEDAL ASSIST]\nSsm=2\n"
        let settings = try Profile.decode(text)
        #expect(settings.basic.lowBatteryProtection == 42)
        #expect(settings.pedalAssist.slowStartMode == 3)
    }

    @Test func missingKeysGetTheOriginalToolsDefaults() throws {
        let settings = try Profile.decode("")
        #expect(settings.basic.lowBatteryProtection == 10)
        #expect(settings.basic.wheelDiameter == .inches(26))  // WD defaults to 10
        #expect(settings.pedalAssist.slowStartMode == 1)
        #expect(settings.pedalAssist.designatedAssistLevel == nil)
        #expect(settings.throttle.mode == .speed)
    }

    @Test(arguments: [
        ("[Basic]\nWD=16", ProfileError.invalidValue(section: "Basic", key: "WD", value: "16")),
        ("[Basic]\nLC=300", ProfileError.invalidValue(section: "Basic", key: "LC", value: "300")),
        ("[Basic]\nLC=abc", ProfileError.invalidValue(section: "Basic", key: "LC", value: "abc")),
        ("[Pedal Assist]\nPT=4", ProfileError.invalidValue(section: "Pedal Assist", key: "PT", value: "4")),
        ("[Pedal Assist]\nSL=241", ProfileError.invalidValue(section: "Pedal Assist", key: "SL", value: "241")),
        ("[Throttle Handle]\nMODE=2", ProfileError.invalidValue(section: "Throttle Handle", key: "MODE", value: "2")),
    ])
    func rejectsInvalidValues(_ text: String, _ error: ProfileError) {
        #expect(throws: error) {
            try Profile.decode(text)
        }
    }
}

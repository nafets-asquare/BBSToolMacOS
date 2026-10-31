import BafangProtocol
import BafangSerial
import Testing
@testable import BBSToolApp

@Suite struct SettingsFormattingTests {
    @Test func displayValuesCoverEveryField() {
        let initial = ControllerSettings.initial
        #expect(initial.basic.displayValues.count == BasicSettings.fieldNames.count)
        #expect(initial.pedalAssist.displayValues.count == PedalAssistSettings.fieldNames.count)
        #expect(initial.throttle.displayValues.count == ThrottleSettings.fieldNames.count)
    }

    @Test func initialSettingsAreEncodable() throws {
        _ = try ControllerSettings.initial.basic.encoded()
        _ = try ControllerSettings.initial.pedalAssist.encoded()
        _ = try ControllerSettings.initial.throttle.encoded()
    }

    @Test func changeSummaryListsChangedFields() {
        let known = ControllerSettings.initial.throttle
        var edited = known
        edited.endVoltage = 42
        edited.speedLimit = nil
        #expect(changeSummary(edited, known: known) == "End Voltage: 3.5 V → 4.2 V\nSpeed Limit: 17 km/h → By display")
    }

    @Test func changeSummaryWithoutChanges() {
        let known = ControllerSettings.initial.pedalAssist
        #expect(changeSummary(known, known: known) == "No changes from the controller's current values.")
    }

    @Test func changeSummaryWhenControllerNotRead() {
        #expect(changeSummary(ControllerSettings.initial.basic, known: nil).contains("have not been read"))
    }

    @Test func choicesIncludeUnusualCurrentValues() {
        #expect(Choices.wheelDiameters(current: WheelDiameter(code: 53)).contains(WheelDiameter(code: 53)))
        #expect(Choices.wheelDiameters(current: .inches(26)) == WheelDiameter.standardChoices)
        #expect(Choices.including(UInt8(7), in: [1, 5, 9]) == [1, 5, 7, 9])
        #expect(Choices.including(UInt8?.none, in: [1, 2]) == [1, 2])
        #expect(Choices.lowBattery(for: nil, current: 20) == Array(18...55))
    }
}

@MainActor
@Suite struct AppModelTests {
    @Test func rejectedWriteSelectsTabAndHighlightsField() {
        let model = AppModel(watchPorts: false)
        model.handle(SessionError.rejected(.throttle, fieldIndex: 5, fieldName: "Start Current"))
        #expect(model.selectedTab == .throttle)
        #expect(model.highlightedField == FieldID(block: .throttle, index: 5))
        #expect(model.alert?.message == "Start Current is out of range. Nothing in Throttle Handle was changed.")
    }

    @Test func notModifiedUntilControllerValuesAreKnown() {
        let model = AppModel(watchPorts: false)
        model.settings.throttle.startCurrent = 50
        #expect(!model.isModified(.throttle))
    }

    @Test func noTransfersWhileDisconnected() {
        let model = AppModel(watchPorts: false)
        #expect(!model.canTransfer)
        model.readAll()
        model.requestWriteAll()
        #expect(model.activity == nil)
        #expect(model.pendingWrite == nil)
    }
}

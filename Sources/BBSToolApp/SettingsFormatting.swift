import BafangProtocol

/// Settings that can describe each payload byte for display, in `fieldNames` order.
protocol DisplayableSettings: SettingsBlock {
    var displayValues: [String] { get }
}

func byDisplay(_ value: UInt8?, unit: String = "") -> String {
    value.map { "\($0)\(unit)" } ?? "By display"
}

extension BasicSettings: DisplayableSettings {
    var displayValues: [String] {
        ["\(lowBatteryProtection) V", "\(currentLimit) A"]
            + assistCurrentLimit.map { "\($0) %" }
            + assistSpeedLimit.map { "\($0) %" }
            + [wheelDiameter.label, "\(speedMeterType.label), \(speedMeterSignals) signals"]
    }
}

extension PedalAssistSettings: DisplayableSettings {
    var displayValues: [String] {
        [
            pedalSensorType.label,
            byDisplay(designatedAssistLevel),
            byDisplay(speedLimit, unit: " km/h"),
            "\(startCurrent) %",
            "\(slowStartMode)",
            "\(startDegree) signals",
            workMode.map(String.init) ?? "Undetermined",
            "\(Int(stopDelay) * 10) ms",
            "\(currentDecay)",
            "\(Int(stopDecay) * 10) ms",
            "\(keepCurrent) %",
        ]
    }
}

extension ThrottleSettings: DisplayableSettings {
    var displayValues: [String] {
        [
            volts(startVoltage),
            volts(endVoltage),
            mode.label,
            byDisplay(designatedAssistLevel),
            byDisplay(speedLimit, unit: " km/h"),
            "\(startCurrent) %",
        ]
    }

    private func volts(_ tenths: UInt8) -> String {
        "\(tenths / 10).\(tenths % 10) V"
    }
}

/// Choices for the pickers. A value read from the controller that is not among the usual
/// choices is added, so it is shown as it is rather than silently replaced.
enum Choices {
    static func lowBattery(for info: GeneralInfo?, current: UInt8) -> [UInt8] {
        including(current, in: Array(info?.nominalVoltage.lowBatteryRange ?? 18...55))
    }

    static func wheelDiameters(current: WheelDiameter) -> [WheelDiameter] {
        var choices = WheelDiameter.standardChoices
        if !choices.contains(current) {
            choices.append(current)
            choices.sort { $0.code < $1.code }
        }
        return choices
    }

    static let assistLevels = Array(UInt8(0)...9)
    static let speedLimits = Array(UInt8(15)...40)
    static let workModes = Array(UInt8(10)...80)
    static let slowStartModes = Array(UInt8(1)...8)

    static func including(_ value: UInt8, in values: [UInt8]) -> [UInt8] {
        values.contains(value) ? values : (values + [value]).sorted()
    }

    static func including(_ value: UInt8?, in values: [UInt8]) -> [UInt8] {
        value.map { including($0, in: values) } ?? values
    }
}

extension ControllerSettings {
    /// The values of the original tool's `Profiles/DefaultProfile.el`, shown before anything
    /// is read or opened.
    static let initial = ControllerSettings(
        basic: BasicSettings(
            lowBatteryProtection: 20,
            currentLimit: 18,
            assistCurrentLimit: Array(stride(from: 10, through: 100, by: 10)),
            assistSpeedLimit: Array(stride(from: 10, through: 100, by: 10)),
            wheelDiameter: .inches(17),
            speedMeterType: .wheelMeter,
            speedMeterSignals: 1
        ),
        pedalAssist: PedalAssistSettings(
            pedalSensorType: .doubleSignal24,
            designatedAssistLevel: nil,
            speedLimit: nil,
            startCurrent: 20,
            slowStartMode: 6,
            startDegree: 20,
            workMode: 10,
            stopDelay: 25,
            currentDecay: 8,
            stopDecay: 20,
            keepCurrent: 20
        ),
        throttle: ThrottleSettings(
            startVoltage: 11,
            endVoltage: 35,
            mode: .speed,
            designatedAssistLevel: 3,
            speedLimit: 17,
            startCurrent: 20
        )
    )
}

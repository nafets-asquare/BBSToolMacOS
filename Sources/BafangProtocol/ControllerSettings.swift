/// All writable settings of a controller.
public struct ControllerSettings: Equatable, Sendable {
    public var basic: BasicSettings
    public var pedalAssist: PedalAssistSettings
    public var throttle: ThrottleSettings

    public init(basic: BasicSettings, pedalAssist: PedalAssistSettings, throttle: ThrottleSettings) {
        self.basic = basic
        self.pedalAssist = pedalAssist
        self.throttle = throttle
    }
}

extension BasicSettings {
    /// Checks the limits that depend on the connected controller, which the controller
    /// itself may not enforce. Returns a description of each problem.
    public func problems(for info: GeneralInfo) -> [String] {
        var problems: [String] = []
        if !info.nominalVoltage.lowBatteryRange.contains(lowBatteryProtection) {
            let range = info.nominalVoltage.lowBatteryRange
            problems.append("Low Battery Protection \(lowBatteryProtection) V is outside \(range.lowerBound)-\(range.upperBound) V for a \(info.nominalVoltage.label) controller")
        }
        if currentLimit > info.maxCurrent {
            problems.append("Current Limit \(currentLimit) A exceeds the controller's maximum of \(info.maxCurrent) A")
        }
        return problems
    }
}

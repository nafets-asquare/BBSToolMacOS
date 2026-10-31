public struct BasicSettings: SettingsBlock {
    public static let block = Block.basic
    public static let assistLevelCount = 10

    public static let fieldNames: [String] =
        ["Low Battery Protection", "Current Limit"]
        + (0..<assistLevelCount).map { "Assist \($0) Current Limit" }
        + (0..<assistLevelCount).map { "Assist \($0) Speed Limit" }
        + ["Wheel Diameter", "Speed Meter"]

    public var lowBatteryProtection: UInt8  // V
    public var currentLimit: UInt8          // A
    public var assistCurrentLimit: [UInt8]  // % for each assist level 0-9
    public var assistSpeedLimit: [UInt8]    // % for each assist level 0-9
    public var wheelDiameter: WheelDiameter
    public var speedMeterType: SpeedMeterType
    public var speedMeterSignals: UInt8     // signals per wheel revolution, 0-63

    public init(
        lowBatteryProtection: UInt8,
        currentLimit: UInt8,
        assistCurrentLimit: [UInt8],
        assistSpeedLimit: [UInt8],
        wheelDiameter: WheelDiameter,
        speedMeterType: SpeedMeterType,
        speedMeterSignals: UInt8
    ) {
        self.lowBatteryProtection = lowBatteryProtection
        self.currentLimit = currentLimit
        self.assistCurrentLimit = assistCurrentLimit
        self.assistSpeedLimit = assistSpeedLimit
        self.wheelDiameter = wheelDiameter
        self.speedMeterType = speedMeterType
        self.speedMeterSignals = speedMeterSignals
    }

    public init(payload: [UInt8]) throws {
        try Self.checkLength(payload)
        lowBatteryProtection = payload[0]
        currentLimit = payload[1]
        assistCurrentLimit = Array(payload[2..<12])
        assistSpeedLimit = Array(payload[12..<22])
        wheelDiameter = WheelDiameter(code: payload[22])
        // Speed meter byte: type in the top two bits, signal count in the lower six
        speedMeterType = try decodeEnum(payload[23] >> 6, field: "Speed Meter Type")
        speedMeterSignals = payload[23] & 0x3F
    }

    public func encoded() throws -> [UInt8] {
        for (name, levels) in [("Assist Current Limit", assistCurrentLimit), ("Assist Speed Limit", assistSpeedLimit)]
        where levels.count != Self.assistLevelCount {
            throw ProtocolError.invalidValue(field: name, value: levels.count)
        }
        guard speedMeterSignals <= 0x3F else {
            throw ProtocolError.invalidValue(field: "Speed Meter Signals", value: Int(speedMeterSignals))
        }
        return [lowBatteryProtection, currentLimit]
            + assistCurrentLimit
            + assistSpeedLimit
            + [wheelDiameter.code, speedMeterType.rawValue << 6 | speedMeterSignals]
    }
}

/// Wheel diameter as the controller stores it, in half inches: 26" is 52 and 700C is 55 (27.5").
public struct WheelDiameter: Hashable, Sendable {
    public var code: UInt8

    public init(code: UInt8) {
        self.code = code
    }

    public static func inches(_ inches: UInt8) -> WheelDiameter {
        WheelDiameter(code: inches * 2)
    }

    public static let c700 = WheelDiameter(code: 55)

    /// The choices offered by the original tool, in its order: 16"-27", 700C, 28"-30".
    public static let standardChoices: [WheelDiameter] =
        (16...27).map(inches) + [c700] + (28...30).map(inches)

    public var label: String {
        if self == .c700 { return "700C" }
        return code.isMultiple(of: 2) ? "\(code / 2)\"" : "\(code / 2).5\""
    }
}

public enum SpeedMeterType: UInt8, Sendable, CaseIterable {
    case wheelMeter = 0
    case motorMeter = 1
    case motorPhase = 3

    public var label: String {
        switch self {
        case .wheelMeter: "External, Wheel Meter"
        case .motorMeter: "Internal, Motor Meter"
        case .motorPhase: "By Motor Phase"
        }
    }
}

public struct ThrottleSettings: SettingsBlock {
    public static let block = Block.throttle

    public static let fieldNames = [
        "Start Voltage", "End Voltage", "Mode", "Designated Assist Level", "Speed Limit", "Start Current",
    ]

    public var startVoltage: UInt8           // x100 mV
    public var endVoltage: UInt8             // x100 mV
    public var mode: ThrottleMode
    public var designatedAssistLevel: UInt8? // 0-9; nil: by display's command
    public var speedLimit: UInt8?            // km/h; nil: by display's command
    public var startCurrent: UInt8           // %

    public init(
        startVoltage: UInt8,
        endVoltage: UInt8,
        mode: ThrottleMode,
        designatedAssistLevel: UInt8?,
        speedLimit: UInt8?,
        startCurrent: UInt8
    ) {
        self.startVoltage = startVoltage
        self.endVoltage = endVoltage
        self.mode = mode
        self.designatedAssistLevel = designatedAssistLevel
        self.speedLimit = speedLimit
        self.startCurrent = startCurrent
    }

    public init(payload: [UInt8]) throws {
        try Self.checkLength(payload)
        startVoltage = payload[0]
        endVoltage = payload[1]
        mode = try decodeEnum(payload[2], field: "Mode")
        designatedAssistLevel = optionalByte(payload[3])
        speedLimit = optionalByte(payload[4])
        startCurrent = payload[5]
    }

    public func encoded() throws -> [UInt8] {
        [
            startVoltage,
            endVoltage,
            mode.rawValue,
            try encodeOptional(designatedAssistLevel, field: "Designated Assist Level"),
            try encodeOptional(speedLimit, field: "Speed Limit"),
            startCurrent,
        ]
    }
}

public enum ThrottleMode: UInt8, Sendable, CaseIterable {
    case speed = 0
    case current = 1

    public var label: String {
        switch self {
        case .speed: "Speed"
        case .current: "Current"
        }
    }
}

public struct PedalAssistSettings: SettingsBlock {
    public static let block = Block.pedalAssist

    public static let fieldNames = [
        "Pedal Sensor Type", "Designated Assist Level", "Speed Limit", "Start Current",
        "Slow-start Mode", "Start Degree", "Work Mode", "Stop Delay",
        "Current Decay", "Stop Decay", "Keep Current",
    ]

    public var pedalSensorType: PedalSensorType
    public var designatedAssistLevel: UInt8?  // 0-9; nil: by display's command
    public var speedLimit: UInt8?             // km/h; nil: by display's command
    public var startCurrent: UInt8            // %
    public var slowStartMode: UInt8           // 1-8
    public var startDegree: UInt8             // signal count
    public var workMode: UInt8?               // angular pedal speed/wheel * 10; nil: undetermined
    public var stopDelay: UInt8               // x10 ms
    public var currentDecay: UInt8            // 1-8
    public var stopDecay: UInt8               // x10 ms
    public var keepCurrent: UInt8             // %

    public init(
        pedalSensorType: PedalSensorType,
        designatedAssistLevel: UInt8?,
        speedLimit: UInt8?,
        startCurrent: UInt8,
        slowStartMode: UInt8,
        startDegree: UInt8,
        workMode: UInt8?,
        stopDelay: UInt8,
        currentDecay: UInt8,
        stopDecay: UInt8,
        keepCurrent: UInt8
    ) {
        self.pedalSensorType = pedalSensorType
        self.designatedAssistLevel = designatedAssistLevel
        self.speedLimit = speedLimit
        self.startCurrent = startCurrent
        self.slowStartMode = slowStartMode
        self.startDegree = startDegree
        self.workMode = workMode
        self.stopDelay = stopDelay
        self.currentDecay = currentDecay
        self.stopDecay = stopDecay
        self.keepCurrent = keepCurrent
    }

    public init(payload: [UInt8]) throws {
        try Self.checkLength(payload)
        pedalSensorType = try decodeEnum(payload[0], field: "Pedal Sensor Type")
        designatedAssistLevel = optionalByte(payload[1])
        speedLimit = optionalByte(payload[2])
        startCurrent = payload[3]
        slowStartMode = payload[4]
        startDegree = payload[5]
        workMode = optionalByte(payload[6])
        stopDelay = payload[7]
        currentDecay = payload[8]
        stopDecay = payload[9]
        keepCurrent = payload[10]
    }

    public func encoded() throws -> [UInt8] {
        [
            pedalSensorType.rawValue,
            try encodeOptional(designatedAssistLevel, field: "Designated Assist Level"),
            try encodeOptional(speedLimit, field: "Speed Limit"),
            startCurrent,
            slowStartMode,
            startDegree,
            try encodeOptional(workMode, field: "Work Mode"),
            stopDelay,
            currentDecay,
            stopDecay,
            keepCurrent,
        ]
    }
}

public enum PedalSensorType: UInt8, Sendable, CaseIterable {
    case none = 0
    case dhSensor12 = 1
    case bbSensor32 = 2
    case doubleSignal24 = 3

    public var label: String {
        switch self {
        case .none: "None"
        case .dhSensor12: "DH-Sensor-12"
        case .bbSensor32: "BB-Sensor-32"
        case .doubleSignal24: "DoubleSignal-24"
        }
    }
}

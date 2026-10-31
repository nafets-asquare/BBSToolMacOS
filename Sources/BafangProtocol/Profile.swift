import Foundation

public enum ProfileError: Error, Equatable, CustomStringConvertible, Sendable {
    case notText
    case invalidValue(section: String, key: String, value: String)

    public var description: String {
        switch self {
        case .notText: "the file is not a text profile"
        case .invalidValue(let section, let key, let value): "[\(section)] \(key)=\(value) is not a valid value"
        }
    }
}

/// Reads and writes the original tool's `.el` profiles.
///
/// Profiles are INI files. Most values are stored as is, but pickers are stored as the
/// position of the entry in the original tool's list (e.g. wheel diameter `WD=10` is the
/// 11th entry, 26"). Missing keys get the same defaults as in the original tool.
///
/// A wheel diameter that is not in the original list (e.g. 26.5" read from a controller)
/// is saved as the nearest entry plus an extra `WDCODE` key holding the exact value. The
/// original tool ignores unknown keys; this one prefers `WDCODE` when present.
public enum Profile {
    public static let fileExtension = "el"

    public static func decode(_ data: Data) throws -> ControllerSettings {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ProfileError.notText
        }
        return try decode(text)
    }

    public static func decode(_ text: String) throws -> ControllerSettings {
        let ini = IniFile(text)
        let basic = Reader(ini: ini, section: "Basic")
        let pas = Reader(ini: ini, section: "Pedal Assist")
        let throttle = Reader(ini: ini, section: "Throttle Handle")

        let wheelDiameter: WheelDiameter
        if ini.value(section: "Basic", key: "WDCODE") != nil {
            wheelDiameter = WheelDiameter(code: try basic.byte("WDCODE", default: 0))
        } else {
            wheelDiameter = try basic.choice("WD", default: 10, from: WheelDiameter.standardChoices)
        }

        return ControllerSettings(
            basic: BasicSettings(
                lowBatteryProtection: try basic.byte("LBP", default: 10),
                currentLimit: try basic.byte("LC", default: 10),
                assistCurrentLimit: try (0..<10).map { try basic.byte("ALC\($0)", default: 10) },
                assistSpeedLimit: try (0..<10).map { try basic.byte("ALBP\($0)", default: 10) },
                wheelDiameter: wheelDiameter,
                speedMeterType: try basic.choice("SMM", default: 0, from: speedMeterTypes),
                speedMeterSignals: try basic.byte("SMS", default: 10)
            ),
            pedalAssist: PedalAssistSettings(
                pedalSensorType: try pas.choice("PT", default: 0, from: PedalSensorType.allCases),
                designatedAssistLevel: try pas.optional("DA", offset: -1),
                speedLimit: try pas.optional("SL", offset: 14),
                startCurrent: try pas.byte("SC", default: 10),
                slowStartMode: try pas.byte("SSM", default: 0, offset: 1),
                startDegree: try pas.byte("SDN", default: 10),
                workMode: try pas.optional("WM", offset: 9),
                stopDelay: try pas.byte("TS", default: 10),
                currentDecay: try pas.byte("CD", default: 10),
                stopDecay: try pas.byte("SD", default: 10),
                keepCurrent: try pas.byte("KC", default: 10)
            ),
            throttle: ThrottleSettings(
                startVoltage: try throttle.byte("SV", default: 10),
                endVoltage: try throttle.byte("EV", default: 10),
                mode: try throttle.choice("MODE", default: 0, from: ThrottleMode.allCases),
                designatedAssistLevel: try throttle.optional("DA", offset: -1),
                speedLimit: try throttle.optional("SL", offset: 14),
                startCurrent: try throttle.byte("SC", default: 10)
            )
        )
    }

    /// Writes the keys in the same order as the original tool, with Windows line endings.
    public static func encode(_ settings: ControllerSettings) -> String {
        let basic = settings.basic
        let pas = settings.pedalAssist
        let throttle = settings.throttle

        var basicKeys: [(String, Int)] = [("LBP", Int(basic.lowBatteryProtection)), ("LC", Int(basic.currentLimit))]
        basicKeys += basic.assistCurrentLimit.enumerated().map { ("ALC\($0.offset)", Int($0.element)) }
        basicKeys += basic.assistSpeedLimit.enumerated().map { ("ALBP\($0.offset)", Int($0.element)) }
        if let index = WheelDiameter.standardChoices.firstIndex(of: basic.wheelDiameter) {
            basicKeys.append(("WD", index))
        } else {
            basicKeys.append(("WD", nearestStandardWheelIndex(basic.wheelDiameter)))
            basicKeys.append(("WDCODE", Int(basic.wheelDiameter.code)))
        }
        basicKeys += [
            ("SMM", speedMeterTypes.firstIndex(of: basic.speedMeterType)!),
            ("SMS", Int(basic.speedMeterSignals)),
        ]

        let pasKeys: [(String, Int)] = [
            ("PT", Int(pas.pedalSensorType.rawValue)),
            ("DA", index(pas.designatedAssistLevel, offset: -1)),
            ("SL", index(pas.speedLimit, offset: 14)),
            ("SSM", Int(pas.slowStartMode) - 1),
            ("WM", index(pas.workMode, offset: 9)),
            ("SC", Int(pas.startCurrent)),
            ("SDN", Int(pas.startDegree)),
            ("TS", Int(pas.stopDelay)),
            ("CD", Int(pas.currentDecay)),
            ("SD", Int(pas.stopDecay)),
            ("KC", Int(pas.keepCurrent)),
        ]

        let throttleKeys: [(String, Int)] = [
            ("SV", Int(throttle.startVoltage)),
            ("EV", Int(throttle.endVoltage)),
            ("MODE", Int(throttle.mode.rawValue)),
            ("DA", index(throttle.designatedAssistLevel, offset: -1)),
            ("SL", index(throttle.speedLimit, offset: 14)),
            ("SC", Int(throttle.startCurrent)),
        ]

        let lines = [("Basic", basicKeys), ("Pedal Assist", pasKeys), ("Throttle Handle", throttleKeys)]
            .flatMap { section, keys in ["[\(section)]"] + keys.map { "\($0)=\($1)" } }
        return lines.map { $0 + "\r\n" }.joined()
    }

    /// Speed meter type list order in the original tool.
    static let speedMeterTypes: [SpeedMeterType] = [.wheelMeter, .motorMeter, .motorPhase]

    /// List position for a "by display"/"undetermined" picker: 0 is nil, otherwise value - offset.
    private static func index(_ value: UInt8?, offset: Int) -> Int {
        value.map { Int($0) - offset } ?? 0
    }

    private static func nearestStandardWheelIndex(_ wheel: WheelDiameter) -> Int {
        let choices = WheelDiameter.standardChoices
        return choices.indices.min { abs(Int(choices[$0].code) - Int(wheel.code)) < abs(Int(choices[$1].code) - Int(wheel.code)) }!
    }

    private struct Reader {
        let ini: IniFile
        let section: String

        private func integer(_ key: String, default defaultValue: Int) throws -> Int {
            guard let text = ini.value(section: section, key: key) else { return defaultValue }
            guard let value = Int(text) else { throw invalid(key, text) }
            return value
        }

        private func invalid(_ key: String, _ value: String) -> ProfileError {
            .invalidValue(section: section, key: key, value: value)
        }

        private func toByte(_ key: String, _ value: Int, stored: Int) throws -> UInt8 {
            guard let byte = UInt8(exactly: value) else { throw invalid(key, String(stored)) }
            return byte
        }

        func byte(_ key: String, default defaultValue: Int, offset: Int = 0) throws -> UInt8 {
            let stored = try integer(key, default: defaultValue)
            return try toByte(key, stored + offset, stored: stored)
        }

        /// 0 means nil ("by display"/"undetermined"); otherwise the value is index + offset.
        func optional(_ key: String, offset: Int) throws -> UInt8? {
            let stored = try integer(key, default: 0)
            guard stored != 0 else { return nil }
            let value = try toByte(key, stored + offset, stored: stored)
            guard value != 0xFF else { throw invalid(key, String(stored)) }
            return value
        }

        func choice<T>(_ key: String, default defaultValue: Int, from choices: [T]) throws -> T {
            let stored = try integer(key, default: defaultValue)
            guard choices.indices.contains(stored) else { throw invalid(key, String(stored)) }
            return choices[stored]
        }
    }
}

/// Minimal INI reader: `[section]` headers and `key=value` lines. Section and key names
/// are matched case-insensitively, as by Windows; `;` and `#` start comment lines.
struct IniFile {
    private var values: [String: [String: String]] = [:]

    init(_ text: String) {
        var section = ""
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{FEFF}")))
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces).lowercased()
            } else if let equals = line.firstIndex(of: "=") {
                let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                values[section, default: [:]][key] = value
            }
        }
    }

    func value(section: String, key: String) -> String? {
        values[section.lowercased()]?[key.lowercased()]
    }
}

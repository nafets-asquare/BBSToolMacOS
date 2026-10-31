import BafangProtocol
import Dispatch

public enum SessionError: Error, CustomStringConvertible, Sendable {
    case notConnected
    /// Settings failed a check against the connected controller; nothing was sent.
    case invalidSettings([String])
    /// The controller rejected a field as out of range; the block was not stored.
    case rejected(Block, fieldIndex: Int, fieldName: String)
    case unknownWriteResult(Block, code: UInt8)
    /// The controller accepted a write, but reading the block back returned different bytes.
    case verificationFailed(Block, written: [UInt8], readBack: [UInt8])

    public var description: String {
        switch self {
        case .notConnected:
            "not connected to a controller"
        case .invalidSettings(let problems):
            "settings not written: " + problems.joined(separator: "; ")
        case .rejected(let block, _, let fieldName):
            "controller rejected \(block.title): \(fieldName) is out of range"
        case .unknownWriteResult(let block, let code):
            "controller gave an unknown reply to writing \(block.title) (code \(code))"
        case .verificationFailed(let block, let written, let readBack):
            "\(block.title) read back differently after writing: wrote \(hex(written)), read \(hex(readBack))"
        }
    }
}

/// A connection to one controller. Operations run one at a time on a dedicated queue,
/// so the blocking serial I/O never occupies Swift's shared concurrency threads.
///
/// A serial port error (e.g. the cable was unplugged) closes the port and ends the
/// connection; timeouts and malformed responses leave it open for a retry.
public actor ControllerSession {
    private let queue = DispatchSerialQueue(label: "BBSTool.ControllerSession")
    private let link: ControllerLink

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// Controller identification; nil while not connected.
    public private(set) var info: GeneralInfo?

    public var isConnected: Bool { info != nil }

    public init(
        path: String,
        options: ControllerLink.Options = ControllerLink.Options(),
        trace: (@Sendable (TraceEvent) -> Void)? = nil
    ) {
        link = ControllerLink(port: SerialPort(path: path), options: options)
        link.trace = trace
    }

    @discardableResult
    public func connect() throws -> GeneralInfo {
        let info = try perform { try link.connect() }
        self.info = info
        return info
    }

    public func disconnect() {
        link.port.close()
        info = nil
    }

    public func read<S: SettingsBlock>(_ type: S.Type) throws -> S {
        try requireConnection()
        return try perform { try link.read(type).settings }
    }

    public func readAll() throws -> ControllerSettings {
        let basic = try read(BasicSettings.self)
        try Task.checkCancellation()
        let pedalAssist = try read(PedalAssistSettings.self)
        try Task.checkCancellation()
        let throttle = try read(ThrottleSettings.self)
        return ControllerSettings(basic: basic, pedalAssist: pedalAssist, throttle: throttle)
    }

    /// Writes one block. With `verify`, reads it back and checks every byte.
    public func write<S: SettingsBlock>(_ settings: S, verify: Bool = true) throws {
        let info = try requireConnection()
        try validate(settings, for: info)
        try writeValidated(settings, verify: verify)
    }

    /// Writes all three blocks in order (basic, pedal assist, throttle), stopping at the
    /// first failure. Every block is validated before anything is sent.
    public func writeAll(_ settings: ControllerSettings, verify: Bool = true) throws {
        let info = try requireConnection()
        try validate(settings.basic, for: info)
        try validate(settings.pedalAssist, for: info)
        try validate(settings.throttle, for: info)

        try writeValidated(settings.basic, verify: verify)
        try Task.checkCancellation()
        try writeValidated(settings.pedalAssist, verify: verify)
        try Task.checkCancellation()
        try writeValidated(settings.throttle, verify: verify)
    }

    private func writeValidated<S: SettingsBlock>(_ settings: S, verify: Bool) throws {
        switch try perform({ try link.write(settings) }) {
        case .accepted:
            break
        case .rejected(let index, let name):
            throw SessionError.rejected(S.block, fieldIndex: index, fieldName: name)
        case .unknown(let code):
            throw SessionError.unknownWriteResult(S.block, code: code)
        }

        guard verify else { return }
        let readBack = try perform { try link.read(S.self).settings }
        if readBack != settings {
            throw SessionError.verificationFailed(S.block, written: try settings.encoded(), readBack: try readBack.encoded())
        }
    }

    /// Encodes the settings (catching values that cannot be sent) and applies the checks
    /// that depend on the connected controller.
    private func validate<S: SettingsBlock>(_ settings: S, for info: GeneralInfo) throws {
        do {
            _ = try settings.encoded()
        } catch let error as ProtocolError {
            throw SessionError.invalidSettings(["\(error)"])
        }
        if let basic = settings as? BasicSettings {
            let problems = basic.problems(for: info)
            if !problems.isEmpty {
                throw SessionError.invalidSettings(problems)
            }
        }
    }

    @discardableResult
    private func requireConnection() throws -> GeneralInfo {
        guard let info else { throw SessionError.notConnected }
        return info
    }

    private func perform<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as SerialError {
            disconnect()
            throw error
        }
    }
}

extension Block {
    public var title: String {
        switch self {
        case .general: "General"
        case .basic: "Basic"
        case .pedalAssist: "Pedal Assist"
        case .throttle: "Throttle Handle"
        }
    }
}

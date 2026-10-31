import BafangProtocol
import BafangSerial
import Foundation

let usage = """
    usage: bbstool ports
           bbstool info [port] [options]             connect and show controller info
           bbstool read [port] [options]             connect and read all settings
           bbstool rewrite <block> [port] [options]  read one block and write the same values back,
                                                     then read again to verify (block: basic, pas, throttle)

    options:
      --trace          print every byte sent and received
      --reopen         close and reopen the port before each request (original tool's behaviour)
      --timeout <ms>   response timeout (default 1500)
      --attempts <n>   connect attempts (default 3)
      --yes            rewrite without asking for confirmation

    If no port is given and exactly one USB serial adapter is present, it is used.
    """

struct Arguments {
    var command: String
    var positionals: [String] = []
    var trace = false
    var confirmed = false
    var options = ControllerLink.Options()

    init(_ arguments: [String]) throws {
        var remaining = arguments[...]
        guard let command = remaining.popFirst() else { throw UsageError() }
        self.command = command
        while let argument = remaining.popFirst() {
            switch argument {
            case "--trace": trace = true
            case "--yes": confirmed = true
            case "--reopen": options.reopenBetweenRequests = true
            case "--timeout": options.responseTimeout = .milliseconds(try Self.integer(remaining.popFirst()))
            case "--attempts": options.connectAttempts = try Self.integer(remaining.popFirst())
            case _ where argument.hasPrefix("-"): throw UsageError()
            default: positionals.append(argument)
            }
        }
    }

    private static func integer(_ text: String?) throws -> Int {
        guard let text, let value = Int(text), value > 0 else { throw UsageError() }
        return value
    }
}

struct UsageError: Error {}

struct Failure: Error, CustomStringConvertible {
    var description: String
}

func resolvePort(_ requested: String?) throws -> String {
    if let requested {
        return requested.hasPrefix("/") ? requested : "/dev/" + requested
    }
    let adapters = PortScanner.likelyAdapters()
    switch adapters.count {
    case 1: return adapters[0]
    case 0: throw Failure(description: "no USB serial adapter found; is the cable plugged in? (see `bbstool ports`)")
    default: throw Failure(description: "several USB serial adapters found, name one:\n  " + adapters.joined(separator: "\n  "))
    }
}

func printPorts() {
    let likely = Set(PortScanner.likelyAdapters())
    let ports = PortScanner.availablePorts()
    if ports.isEmpty {
        print("no serial ports found")
    }
    for port in ports {
        print(likely.contains(port) ? "\(port)  (USB serial adapter)" : port)
    }
}

@Sendable func printTrace(_ event: TraceEvent) {
    let timestamp = Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().secondFraction(.fractional(3)))
    switch event {
    case .sent(let bytes): print("  \(timestamp) → \(hex(bytes))")
    case .received(let bytes): print("  \(timestamp) ← \(hex(bytes))")
    case .trailing(let bytes): print("  \(timestamp) ← after response: \(hex(bytes))")
    }
}

func row(_ label: String, _ value: String) {
    print("  " + label.padding(toLength: 28, withPad: " ", startingAt: 0) + value)
}

func byDisplay(_ value: UInt8?, unit: String = "") -> String {
    value.map { "\($0)\(unit)" } ?? "by display"
}

func printInfo(_ info: GeneralInfo) {
    print("Controller")
    row("Manufacturer", info.manufacturer)
    row("Model", info.model)
    row("Hardware version", "V" + info.hardwareVersion)
    row("Firmware version", "V" + info.firmwareVersion)
    row("Nominal voltage", info.nominalVoltage.label)
    row("Max current", "\(info.maxCurrent) A")
}

func printHeader<S: SettingsBlock>(_ settings: S) throws {
    print("")
    print(S.block.title)
    row("Raw", hex(try settings.encoded()))
}

func printSettings(_ settings: BasicSettings) throws {
    try printHeader(settings)
    row("Low battery protection", "\(settings.lowBatteryProtection) V")
    row("Current limit", "\(settings.currentLimit) A")
    for level in 0..<BasicSettings.assistLevelCount {
        row("Assist \(level)", "current \(settings.assistCurrentLimit[level]) %, speed \(settings.assistSpeedLimit[level]) %")
    }
    row("Wheel diameter", settings.wheelDiameter.label)
    row("Speed meter type", settings.speedMeterType.label)
    row("Speed meter signals", "\(settings.speedMeterSignals)")
}

func printSettings(_ settings: PedalAssistSettings) throws {
    try printHeader(settings)
    row("Pedal sensor type", settings.pedalSensorType.label)
    row("Designated assist level", byDisplay(settings.designatedAssistLevel))
    row("Speed limit", byDisplay(settings.speedLimit, unit: " km/h"))
    row("Start current", "\(settings.startCurrent) %")
    row("Slow-start mode", "\(settings.slowStartMode)")
    row("Start degree", "\(settings.startDegree) signals")
    row("Work mode", settings.workMode.map(String.init) ?? "undetermined")
    row("Stop delay", "\(Int(settings.stopDelay) * 10) ms")
    row("Current decay", "\(settings.currentDecay)")
    row("Stop decay", "\(Int(settings.stopDecay) * 10) ms")
    row("Keep current", "\(settings.keepCurrent) %")
}

func printSettings(_ settings: ThrottleSettings) throws {
    try printHeader(settings)
    row("Start voltage", String(format: "%.1f V", Double(settings.startVoltage) / 10))
    row("End voltage", String(format: "%.1f V", Double(settings.endVoltage) / 10))
    row("Mode", settings.mode.label)
    row("Designated assist level", byDisplay(settings.designatedAssistLevel))
    row("Speed limit", byDisplay(settings.speedLimit, unit: " km/h"))
    row("Start current", "\(settings.startCurrent) %")
}

/// Reads a block, writes the identical values back, and verifies them by reading again.
func rewrite<S: SettingsBlock>(_ type: S.Type, session: ControllerSession, confirmed: Bool) async throws {
    let settings = try await session.read(type)
    print("\n\(S.block.title) currently holds: \(hex(try settings.encoded()))")
    print("This writes the same values back:  \(hex(try Packet.write(settings)))")

    if !confirmed {
        print("Type \"yes\" to write: ", terminator: "")
        fflush(stdout)
        guard readLine()?.trimmingCharacters(in: .whitespaces).lowercased() == "yes" else {
            print("Nothing written.")
            return
        }
    }

    try await session.write(settings, verify: true)
    print("Written. The controller accepted it and the read-back is identical.")
}

func run(_ arguments: Arguments) async throws {
    switch (arguments.command, arguments.positionals.count) {
    case ("ports", 0):
        printPorts()

    case ("info", 0...1), ("read", 0...1):
        try await withSession(arguments, port: arguments.positionals.first) { session in
            guard arguments.command == "read" else { return }
            let settings = try await session.readAll()
            try printSettings(settings.basic)
            try printSettings(settings.pedalAssist)
            try printSettings(settings.throttle)
        }

    case ("rewrite", 1...2):
        let block = arguments.positionals[0]
        guard ["basic", "pas", "throttle"].contains(block) else { throw UsageError() }
        try await withSession(arguments, port: arguments.positionals.dropFirst().first) { session in
            switch block {
            case "basic": try await rewrite(BasicSettings.self, session: session, confirmed: arguments.confirmed)
            case "pas": try await rewrite(PedalAssistSettings.self, session: session, confirmed: arguments.confirmed)
            default: try await rewrite(ThrottleSettings.self, session: session, confirmed: arguments.confirmed)
            }
        }

    default:
        throw UsageError()
    }
}

/// Connects, prints the controller info, runs `body`, and disconnects whether or not it succeeded.
func withSession(_ arguments: Arguments, port: String?, _ body: (ControllerSession) async throws -> Void) async throws {
    let path = try resolvePort(port)
    print("Port: \(path)\n")
    let session = ControllerSession(path: path, options: arguments.options, trace: arguments.trace ? printTrace : nil)
    do {
        printInfo(try await session.connect())
        try await body(session)
    } catch {
        await session.disconnect()
        throw error
    }
    await session.disconnect()
}

// Keep progress output in order with errors on stderr, and visible before a slow exchange
setvbuf(stdout, nil, _IOLBF, 0)

do {
    try await run(Arguments(Array(CommandLine.arguments.dropFirst())))
} catch is UsageError {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

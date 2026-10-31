import BafangProtocol
import BafangSerial
import Foundation

let usage = """
    usage: bbstool ports
           bbstool info [port] [options]    connect and show controller info
           bbstool read [port] [options]    connect and read all settings (never writes)

    options:
      --trace          print every byte sent and received
      --reopen         close and reopen the port before each request (original tool's behaviour)
      --timeout <ms>   response timeout (default 1500)
      --attempts <n>   connect attempts (default 3)

    If no port is given and exactly one USB serial adapter is present, it is used.
    """

struct Arguments {
    var command: String
    var port: String?
    var trace = false
    var options = ControllerLink.Options()

    init(_ arguments: [String]) throws {
        var remaining = arguments[...]
        guard let command = remaining.popFirst() else { throw UsageError() }
        self.command = command
        while let argument = remaining.popFirst() {
            switch argument {
            case "--trace": trace = true
            case "--reopen": options.reopenBetweenRequests = true
            case "--timeout": options.responseTimeout = .milliseconds(try Self.integer(remaining.popFirst()))
            case "--attempts": options.connectAttempts = try Self.integer(remaining.popFirst())
            case _ where argument.hasPrefix("-"): throw UsageError()
            default:
                guard port == nil else { throw UsageError() }
                port = argument
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

func printTrace(_ event: TraceEvent) {
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

func printHeader(_ title: String, _ response: DataResponse) {
    print("")
    print(title)
    row("Raw", hex(response.payload))
}

func printBasic(_ settings: BasicSettings, _ response: DataResponse) {
    printHeader("Basic", response)
    row("Low battery protection", "\(settings.lowBatteryProtection) V")
    row("Current limit", "\(settings.currentLimit) A")
    for level in 0..<BasicSettings.assistLevelCount {
        row("Assist \(level)", "current \(settings.assistCurrentLimit[level]) %, speed \(settings.assistSpeedLimit[level]) %")
    }
    row("Wheel diameter", settings.wheelDiameter.label)
    row("Speed meter type", settings.speedMeterType.label)
    row("Speed meter signals", "\(settings.speedMeterSignals)")
}

func printPedalAssist(_ settings: PedalAssistSettings, _ response: DataResponse) {
    printHeader("Pedal Assist", response)
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

func printThrottle(_ settings: ThrottleSettings, _ response: DataResponse) {
    printHeader("Throttle Handle", response)
    row("Start voltage", String(format: "%.1f V", Double(settings.startVoltage) / 10))
    row("End voltage", String(format: "%.1f V", Double(settings.endVoltage) / 10))
    row("Mode", settings.mode.label)
    row("Designated assist level", byDisplay(settings.designatedAssistLevel))
    row("Speed limit", byDisplay(settings.speedLimit, unit: " km/h"))
    row("Start current", "\(settings.startCurrent) %")
}

func run(_ arguments: Arguments) throws {
    switch arguments.command {
    case "ports":
        printPorts()

    case "info", "read":
        let path = try resolvePort(arguments.port)
        print("Port: \(path)\n")
        let link = ControllerLink(port: SerialPort(path: path), options: arguments.options)
        if arguments.trace {
            link.trace = printTrace
        }
        defer { link.port.close() }

        printInfo(try link.connect())
        guard arguments.command == "read" else { return }

        let basic = try link.read(BasicSettings.self)
        printBasic(basic.settings, basic.response)
        let pedalAssist = try link.read(PedalAssistSettings.self)
        printPedalAssist(pedalAssist.settings, pedalAssist.response)
        let throttle = try link.read(ThrottleSettings.self)
        printThrottle(throttle.settings, throttle.response)

    default:
        throw UsageError()
    }
}

// Keep progress output in order with errors on stderr, and visible before a slow exchange
setvbuf(stdout, nil, _IOLBF, 0)

do {
    try run(Arguments(Array(CommandLine.arguments.dropFirst())))
} catch is UsageError {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

import BafangProtocol
import Foundation
import Testing
@testable import BafangSerial

let generalPayload = Array("HZXTSZZ610".utf8) + Array("2001".utf8) + [2, 30]
let basicPayload: [UInt8] = [41, 25] + Array(stride(from: 10, through: 100, by: 10)) + Array(repeating: 100, count: 10) + [58, 1]
let pedalAssistPayload: [UInt8] = [3, 0xFF, 0xFF, 20, 5, 4, 10, 8, 4, 8, 20]
let throttlePayload: [UInt8] = [11, 35, 1, 0xFF, 0xFF, 20]

func standardReplies() -> [UInt8: [UInt8]] {
    [
        Block.general.rawValue: dataResponse(.general, generalPayload),
        Block.basic.rawValue: dataResponse(.basic, basicPayload),
        Block.pedalAssist.rawValue: dataResponse(.pedalAssist, pedalAssistPayload),
        Block.throttle.rawValue: dataResponse(.throttle, throttlePayload),
    ]
}

func fastOptions() -> ControllerLink.Options {
    var options = ControllerLink.Options()
    options.responseTimeout = .milliseconds(400)
    options.delayBeforeRequest = .milliseconds(5)
    options.trailingListen = .milliseconds(20)
    return options
}

/// Pseudo-terminals are shared system resources, so these tests run one at a time.
@Suite(.serialized) struct ControllerLinkTests {
    @Test func readsAllBlocksDeliveredByteByByte() throws {
        let fake = try FakeController(script: .init(replies: standardReplies()))
        let link = ControllerLink(port: SerialPort(path: fake.path), options: fastOptions())
        defer { link.port.close() }

        let info = try link.connect()
        #expect(info.model == "SZZ6")
        #expect(info.nominalVoltage == .v48)

        let basic = try link.read(BasicSettings.self)
        #expect(basic.settings.wheelDiameter == .inches(29))
        #expect(basic.response.checksumMatches)

        let pedalAssist = try link.read(PedalAssistSettings.self)
        #expect(pedalAssist.settings.speedLimit == nil)
        #expect(pedalAssist.settings.pedalSensorType == .doubleSignal24)

        let throttle = try link.read(ThrottleSettings.self)
        #expect(throttle.settings.mode == .current)

        #expect(fake.requests == [Packet.connect, Packet.read(.basic), Packet.read(.pedalAssist), Packet.read(.throttle)])
    }

    @Test func connectRetriesWhenControllerDoesNotAnswer() throws {
        var script = FakeController.Script(replies: standardReplies())
        script.ignoredConnects = 2
        let fake = try FakeController(script: script)
        let link = ControllerLink(port: SerialPort(path: fake.path), options: fastOptions())
        defer { link.port.close() }

        #expect(try link.connect().manufacturer == "HZXT")
        #expect(fake.requests.count == 3)
    }

    @Test func connectGivesUpAfterAttempts() throws {
        let fake = try FakeController(script: .init())
        var options = fastOptions()
        options.connectAttempts = 2
        options.responseTimeout = .milliseconds(100)
        let link = ControllerLink(port: SerialPort(path: fake.path), options: options)
        defer { link.port.close() }

        #expect {
            try link.connect()
        } throws: { error in
            guard case LinkError.timeout(.data(.general), let received) = error else { return false }
            return received.isEmpty
        }
        #expect(fake.requests.count == 2)
    }

    @Test func wrongLengthIsReportedWithReceivedBytes() throws {
        var replies = standardReplies()
        replies[Block.basic.rawValue] = dataResponse(.basic, Array(basicPayload.prefix(20)))
        let fake = try FakeController(script: .init(replies: replies, chunkSize: 30))
        let link = ControllerLink(port: SerialPort(path: fake.path), options: fastOptions())
        defer { link.port.close() }

        try link.connect()
        #expect {
            try link.read(BasicSettings.self)
        } throws: { error in
            guard case LinkError.malformed(.wrongPayloadLength(.basic, expected: 24, actual: 20), let received) = error
            else { return false }
            return received.starts(with: [0x52, 20])
        }
    }

    @Test func unknownValueIsReportedAsMalformed() throws {
        var replies = standardReplies()
        var payload = throttlePayload
        payload[2] = 7
        replies[Block.throttle.rawValue] = dataResponse(.throttle, payload)
        let fake = try FakeController(script: .init(replies: replies, chunkSize: 30))
        let link = ControllerLink(port: SerialPort(path: fake.path), options: fastOptions())
        defer { link.port.close() }

        try link.connect()
        #expect {
            try link.read(ThrottleSettings.self)
        } throws: { error in
            guard case LinkError.malformed(.unexpectedValue(field: "Mode", value: 7), _) = error else { return false }
            return true
        }
    }

    @Test func badChecksumIsRejected() throws {
        var replies = standardReplies()
        replies[Block.throttle.rawValue]![8] &+= 1
        let fake = try FakeController(script: .init(replies: replies, chunkSize: 30))
        let link = ControllerLink(port: SerialPort(path: fake.path), options: fastOptions())
        defer { link.port.close() }

        #expect {
            try link.read(ThrottleSettings.self)
        } throws: { error in
            guard case LinkError.malformed(.checksumMismatch(.throttle, expected: _, actual: _), _) = error
            else { return false }
            return true
        }
    }

    @Test func traceReportsTrafficAndTrailingBytes() throws {
        var replies = standardReplies()
        replies[Block.throttle.rawValue] = dataResponse(.throttle, throttlePayload) + [0xAA, 0xBB]
        let fake = try FakeController(script: .init(replies: replies, chunkSize: 30))
        let link = ControllerLink(port: SerialPort(path: fake.path), options: fastOptions())
        defer { link.port.close() }

        let events = Locked<[TraceEvent]>([])
        link.trace = { event in events.withLock { $0.append(event) } }
        _ = try link.read(ThrottleSettings.self)

        let recorded = events.withLock { $0 }
        guard case .sent(let sent) = recorded.first else {
            Issue.record("first event should be the request")
            return
        }
        #expect(sent == Packet.read(.throttle))
        guard case .trailing(let trailing) = recorded.last else {
            Issue.record("last event should be the trailing bytes")
            return
        }
        #expect(trailing == [0xAA, 0xBB])
    }

    @Test func reopenBetweenRequests() throws {
        let fake = try FakeController(script: .init(replies: standardReplies(), chunkSize: 30))
        var options = fastOptions()
        options.reopenBetweenRequests = true
        let link = ControllerLink(port: SerialPort(path: fake.path), options: options)
        defer { link.port.close() }

        try link.connect()
        #expect(try link.read(PedalAssistSettings.self).settings.slowStartMode == 5)
    }

    @Test func openingMissingPortFails() {
        let port = SerialPort(path: "/dev/cu.does-not-exist")
        #expect(throws: SerialError.self) {
            try port.open()
        }
    }
}

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock { body(&value) }
    }
}

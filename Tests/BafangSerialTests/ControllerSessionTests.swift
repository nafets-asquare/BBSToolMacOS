import BafangProtocol
import Foundation
import Testing
@testable import BafangSerial

private func makeSession(_ script: FakeController.Script) throws -> (FakeController, ControllerSession) {
    var script = script
    script.chunkSize = 30
    let fake = try FakeController(script: script)
    return (fake, ControllerSession(path: fake.path, options: fastOptions()))
}

private func writes(_ fake: FakeController) -> [[UInt8]] {
    fake.requests.filter { $0[0] == Opcode.write.rawValue }
}

@Suite(.serialized) struct ControllerSessionTests {
    @Test func readRequiresConnection() async throws {
        let (fake, session) = try makeSession(.init(replies: standardReplies()))
        await #expect {
            try await session.read(ThrottleSettings.self)
        } throws: { error in
            guard case SessionError.notConnected = error else { return false }
            return true
        }
        #expect(fake.requests.isEmpty)
    }

    @Test func connectAndReadAll() async throws {
        let (_, session) = try makeSession(.init(replies: standardReplies()))
        let info = try await session.connect()
        #expect(info.maxCurrent == 30)
        #expect(await session.isConnected)

        let settings = try await session.readAll()
        #expect(settings.basic.currentLimit == 25)
        #expect(settings.pedalAssist.slowStartMode == 5)
        #expect(settings.throttle.mode == .current)
        await session.disconnect()
        #expect(await !session.isConnected)
    }

    @Test func writeIsVerifiedByReadingBack() async throws {
        let (fake, session) = try makeSession(.init(replies: standardReplies()))
        try await session.connect()
        var throttle = try await session.read(ThrottleSettings.self)
        throttle.startCurrent = 30

        try await session.write(throttle)

        let requests = fake.requests
        #expect(requests.suffix(2) == [try Packet.write(throttle), Packet.read(.throttle)])
        #expect(try await session.read(ThrottleSettings.self) == throttle)
    }

    @Test func writeWithoutVerificationSkipsReadBack() async throws {
        let (fake, session) = try makeSession(.init(replies: standardReplies()))
        try await session.connect()
        let throttle = try await session.read(ThrottleSettings.self)
        try await session.write(throttle, verify: false)
        #expect(fake.requests.last == (try Packet.write(throttle)))
    }

    @Test func rejectedWriteNamesTheField() async throws {
        var script = FakeController.Script(replies: standardReplies())
        script.writeRejections[Block.pedalAssist.rawValue] = 3
        let (fake, session) = try makeSession(script)
        try await session.connect()
        let pedalAssist = try await session.read(PedalAssistSettings.self)

        await #expect {
            try await session.write(pedalAssist)
        } throws: { error in
            guard case SessionError.rejected(.pedalAssist, fieldIndex: 3, fieldName: "Start Current") = error
            else { return false }
            return true
        }
        // No read-back after a rejection
        #expect(fake.requests.last?[0] == Opcode.write.rawValue)
        #expect(await session.isConnected)
    }

    @Test func unknownWriteResult() async throws {
        var script = FakeController.Script(replies: standardReplies())
        script.writeRejections[Block.throttle.rawValue] = 0x7F
        let (_, session) = try makeSession(script)
        try await session.connect()
        let throttle = try await session.read(ThrottleSettings.self)

        await #expect {
            try await session.write(throttle)
        } throws: { error in
            guard case SessionError.unknownWriteResult(.throttle, code: 0x7F) = error else { return false }
            return true
        }
    }

    @Test func writeThatDidNotStickFailsVerification() async throws {
        var script = FakeController.Script(replies: standardReplies())
        script.discardWrites = true
        let (_, session) = try makeSession(script)
        try await session.connect()
        var throttle = try await session.read(ThrottleSettings.self)
        throttle.endVoltage = 40

        await #expect {
            try await session.write(throttle)
        } throws: { error in
            guard case SessionError.verificationFailed(.throttle, let written, let readBack) = error else { return false }
            return written[1] == 40 && readBack[1] == 35
        }
    }

    @Test func writeAllWritesBlocksInOrder() async throws {
        let (fake, session) = try makeSession(.init(replies: standardReplies()))
        try await session.connect()
        var settings = try await session.readAll()
        settings.basic.wheelDiameter = .c700
        settings.pedalAssist.keepCurrent = 60
        settings.throttle.speedLimit = 25

        try await session.writeAll(settings)

        #expect(writes(fake).map { $0[1] } == [0x52, 0x53, 0x54])
        #expect(try await session.readAll() == settings)
    }

    @Test func writeAllStopsAtFirstRejection() async throws {
        var script = FakeController.Script(replies: standardReplies())
        script.writeRejections[Block.pedalAssist.rawValue] = 0
        let (fake, session) = try makeSession(script)
        try await session.connect()
        let settings = try await session.readAll()

        await #expect(throws: SessionError.self) {
            try await session.writeAll(settings)
        }
        #expect(writes(fake).map { $0[1] } == [0x52, 0x53])
    }

    @Test func writeAllValidatesEveryBlockBeforeSending() async throws {
        let (fake, session) = try makeSession(.init(replies: standardReplies()))
        try await session.connect()
        var settings = try await session.readAll()
        settings.throttle.speedLimit = 0xFF  // cannot be encoded

        await #expect {
            try await session.writeAll(settings)
        } throws: { error in
            guard case SessionError.invalidSettings = error else { return false }
            return true
        }
        #expect(writes(fake).isEmpty)
    }

    @Test func currentLimitAboveControllerMaximumIsRefused() async throws {
        let (fake, session) = try makeSession(.init(replies: standardReplies()))
        try await session.connect()
        var basic = try await session.read(BasicSettings.self)
        basic.currentLimit = 31

        await #expect {
            try await session.write(basic)
        } throws: { error in
            guard case SessionError.invalidSettings(let problems) = error else { return false }
            return problems == ["Current Limit 31 A exceeds the controller's maximum of 30 A"]
        }
        #expect(writes(fake).isEmpty)
    }

    @Test func lowBatteryOutsideVoltageRangeIsRefused() async throws {
        let (fake, session) = try makeSession(.init(replies: standardReplies()))
        try await session.connect()
        var basic = try await session.read(BasicSettings.self)
        basic.lowBatteryProtection = 30  // 48V controller allows 38-43

        await #expect(throws: SessionError.self) {
            try await session.write(basic)
        }
        #expect(writes(fake).isEmpty)
    }

    @Test func deviceDisappearingEndsConnection() async throws {
        let (fake, session) = try makeSession(.init(replies: standardReplies()))
        try await session.connect()
        fake.stop()

        await #expect(throws: SerialError.self) {
            try await session.read(ThrottleSettings.self)
        }
        #expect(await !session.isConnected)
    }
}

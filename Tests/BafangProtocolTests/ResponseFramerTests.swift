import Testing
@testable import BafangProtocol

/// A read response as the controller is expected to send it: block, length, payload, checksum.
private func readResponse(_ block: Block, _ payload: [UInt8]) -> [UInt8] {
    let body = [block.rawValue, UInt8(payload.count)] + payload
    return body + [Packet.checksum(body)]
}

@Suite struct ResponseFramerTests {
    let throttlePayload: [UInt8] = [11, 35, 0, 3, 0xFF, 20]

    @Test func completeResponse() throws {
        var framer = ResponseFramer()
        framer.append(readResponse(.throttle, throttlePayload))
        let response = try framer.next(expecting: .data(.throttle))
        guard case .data(let data) = response else {
            Issue.record("expected data response, got \(String(describing: response))")
            return
        }
        #expect(data.payload == throttlePayload)
        #expect(data.checksumMatches)
        #expect(framer.buffer.isEmpty)
    }

    @Test func responseArrivingByteByByte() throws {
        var framer = ResponseFramer()
        let bytes = readResponse(.throttle, throttlePayload)
        for byte in bytes.dropLast() {
            framer.append([byte])
            #expect(try framer.next(expecting: .data(.throttle)) == nil)
        }
        framer.append([bytes.last!])
        #expect(try framer.next(expecting: .data(.throttle)) != nil)
    }

    @Test func discardsBytesBeforeBlockID() throws {
        var framer = ResponseFramer()
        framer.append([0x00, 0x11, 0xFF] + readResponse(.throttle, throttlePayload))
        guard case .data(let data) = try framer.next(expecting: .data(.throttle)) else {
            Issue.record("expected data response")
            return
        }
        #expect(data.payload == throttlePayload)
    }

    @Test func discardsBufferWithoutBlockID() throws {
        var framer = ResponseFramer()
        framer.append([0x00, 0x01, 0x02])
        #expect(try framer.next(expecting: .data(.basic)) == nil)
        #expect(framer.buffer.isEmpty)
    }

    @Test func keepsTrailingBytes() throws {
        var framer = ResponseFramer()
        framer.append(readResponse(.throttle, throttlePayload) + [0x54])
        _ = try framer.next(expecting: .data(.throttle))
        #expect(framer.buffer == [0x54])
    }

    @Test func wrongLengthThrows() {
        var framer = ResponseFramer()
        framer.append([0x53, 0x0A])
        #expect(throws: ProtocolError.wrongPayloadLength(.pedalAssist, expected: 11, actual: 10)) {
            try framer.next(expecting: .data(.pedalAssist))
        }
        #expect(framer.buffer.isEmpty)
    }

    @Test func generalBlockUsesReportedLength() throws {
        var framer = ResponseFramer()
        let payload = Array("HZXTSZZ610".utf8) + Array("2001".utf8) + [2, 25]
        framer.append(readResponse(.general, payload))
        guard case .data(let data) = try framer.next(expecting: .data(.general)) else {
            Issue.record("expected data response")
            return
        }
        #expect(try GeneralInfo(payload: data.payload).maxCurrent == 25)
    }

    @Test func badChecksumIsReportedNotRejected() throws {
        var framer = ResponseFramer()
        var bytes = readResponse(.throttle, throttlePayload)
        bytes[bytes.count - 1] &+= 1
        framer.append(bytes)
        guard case .data(let data) = try framer.next(expecting: .data(.throttle)) else {
            Issue.record("expected data response")
            return
        }
        #expect(!data.checksumMatches)
    }

    @Test func writeAck() throws {
        var framer = ResponseFramer()
        framer.append([0x52])
        #expect(try framer.next(expecting: .writeAck(.basic)) == nil)
        framer.append([0x18])
        #expect(try framer.next(expecting: .writeAck(.basic)) == nil)
        framer.append([0x6A])
        #expect(try framer.next(expecting: .writeAck(.basic)) == .writeAck(.basic, code: 24))
        #expect(framer.buffer.isEmpty)
    }

    @Test func writeAckWithBadChecksumThrows() {
        var framer = ResponseFramer()
        framer.append([0x54, 0x06, 0x5B])
        #expect(throws: ProtocolError.checksumMismatch(.throttle, expected: 0x5A, actual: 0x5B)) {
            try framer.next(expecting: .writeAck(.throttle))
        }
    }
}

/// A block's contents as returned by a read: block ID, payload length, payload, checksum.
public struct DataResponse: Equatable, Sendable {
    public var block: Block
    public var payload: [UInt8]
    public var checksum: UInt8

    /// Checksum computed the same way as for write requests (block + length + payload).
    /// The original tool never checked response checksums; this formula was confirmed
    /// against a BBSHD for all four blocks.
    public var expectedChecksum: UInt8 {
        Packet.checksum([block.rawValue, UInt8(payload.count)] + payload)
    }

    public var checksumMatches: Bool { checksum == expectedChecksum }
}

public enum Response: Equatable, Sendable {
    case data(DataResponse)
    /// Reply to a write: block ID and a result code, see `SettingsBlock.writeResult(code:)`.
    /// On the wire a checksum follows (block + code); the framer verifies it.
    case writeAck(Block, code: UInt8)
}

public enum Expectation: Equatable, Sendable {
    case data(Block)
    case writeAck(Block)
}

/// Collects bytes from the serial port and splits them into responses.
///
/// The original tool assumed each receive event held exactly one complete response;
/// at 1200 baud a response can arrive in several pieces, so bytes are buffered here
/// until a whole response is available.
public struct ResponseFramer: Sendable {
    public private(set) var buffer: [UInt8] = []

    public init() {}

    public mutating func append(_ bytes: some Sequence<UInt8>) {
        buffer.append(contentsOf: bytes)
    }

    public mutating func reset() {
        buffer.removeAll()
    }

    /// Removes and returns the next complete response, or returns nil if more bytes are
    /// needed. Bytes before the expected block ID are discarded.
    public mutating func next(expecting expectation: Expectation) throws -> Response? {
        let block = switch expectation {
        case .data(let block), .writeAck(let block): block
        }

        guard let start = buffer.firstIndex(of: block.rawValue) else {
            buffer.removeAll()
            return nil
        }
        buffer.removeFirst(start)

        switch expectation {
        case .writeAck:
            // Block, code, checksum. The original tool read only the first two bytes;
            // the checksum was found on a BBSHD (54 06 5A).
            guard buffer.count >= 3 else { return nil }
            let code = buffer[1]
            let checksum = buffer[2]
            buffer.removeFirst(3)
            let expected = Packet.checksum([block.rawValue, code])
            guard checksum == expected else {
                throw ProtocolError.checksumMismatch(block, expected: expected, actual: checksum)
            }
            return .writeAck(block, code: code)

        case .data:
            guard buffer.count >= 2 else { return nil }
            let length = Int(buffer[1])
            if let expected = block.payloadLength, length != expected {
                buffer.removeAll()
                throw ProtocolError.wrongPayloadLength(block, expected: expected, actual: length)
            }
            let total = 2 + length + 1
            guard buffer.count >= total else { return nil }
            let response = DataResponse(block: block, payload: Array(buffer[2..<(2 + length)]), checksum: buffer[total - 1])
            buffer.removeFirst(total)
            return .data(response)
        }
    }
}

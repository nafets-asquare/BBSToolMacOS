/// Builds the byte sequences sent to the controller.
public enum Packet {
    /// Sum of the bytes modulo 256.
    public static func checksum(_ bytes: some Sequence<UInt8>) -> UInt8 {
        bytes.reduce(0, &+)
    }

    /// Request for the general info block, sent when connecting.
    /// The `04 B0` bytes are copied from the original tool; their meaning is unknown.
    public static var connect: [UInt8] {
        let body: [UInt8] = [Block.general.rawValue, 0x04, 0xB0]
        return [Opcode.read.rawValue] + body + [checksum(body)]
    }

    public static func read(_ block: Block) -> [UInt8] {
        [Opcode.read.rawValue, block.rawValue]
    }

    /// Write request: opcode, block, payload length, payload, then a checksum over
    /// everything except the opcode.
    public static func write(_ block: Block, payload: [UInt8]) throws -> [UInt8] {
        if let expected = block.payloadLength, payload.count != expected {
            throw ProtocolError.wrongPayloadLength(block, expected: expected, actual: payload.count)
        }
        let body = [block.rawValue, UInt8(payload.count)] + payload
        return [Opcode.write.rawValue] + body + [checksum(body)]
    }

    public static func write<S: SettingsBlock>(_ settings: S) throws -> [UInt8] {
        try write(S.block, payload: settings.encoded())
    }
}

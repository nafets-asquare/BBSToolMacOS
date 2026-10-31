/// Memory blocks of the controller. The block ID is the second byte of every request
/// and the first byte of every response.
public enum Block: UInt8, Sendable, CaseIterable {
    case general = 0x51
    case basic = 0x52
    case pedalAssist = 0x53
    case throttle = 0x54

    /// Number of payload bytes in a read response or write request.
    /// `nil` for the general block, whose length is taken from the response itself.
    public var payloadLength: Int? {
        switch self {
        case .general: nil
        case .basic: 24
        case .pedalAssist: 11
        case .throttle: 6
        }
    }
}

public enum Opcode: UInt8, Sendable {
    case read = 0x11
    case write = 0x16
}

public enum ProtocolError: Error, Equatable, Sendable {
    /// A payload did not have the length the block requires.
    case wrongPayloadLength(Block, expected: Int, actual: Int)
    /// The controller reported a value this tool does not know how to represent.
    case unexpectedValue(field: String, value: UInt8)
    /// A setting holds a value that cannot be encoded for the controller.
    case invalidValue(field: String, value: Int)
}

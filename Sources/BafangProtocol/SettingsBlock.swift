/// A writable settings block (basic, pedal assist or throttle).
public protocol SettingsBlock: Equatable, Sendable {
    static var block: Block { get }
    /// Display name of each payload byte, in payload order. Write errors from the
    /// controller are reported as an index into this list.
    static var fieldNames: [String] { get }

    init(payload: [UInt8]) throws
    func encoded() throws -> [UInt8]
}

public enum WriteResult: Equatable, Sendable {
    case accepted
    /// The controller rejected the field at this payload index as out of range.
    case rejected(fieldIndex: Int, fieldName: String)
    case unknown(code: UInt8)
}

extension SettingsBlock {
    static var payloadLength: Int { block.payloadLength! }

    /// Interprets the second byte of the controller's reply to a write.
    ///
    /// A code equal to the payload length means success; a smaller code is the index of
    /// the rejected field. The original tool mapped basic-block codes 2–21 by alternating
    /// current/speed limits per assist level, which does not match the payload order that
    /// every other code follows; this uses payload order. Verify on hardware.
    public static func writeResult(code: UInt8) -> WriteResult {
        let index = Int(code)
        if index == payloadLength { return .accepted }
        if index < fieldNames.count { return .rejected(fieldIndex: index, fieldName: fieldNames[index]) }
        return .unknown(code: code)
    }

    static func checkLength(_ payload: [UInt8]) throws {
        guard payload.count == payloadLength else {
            throw ProtocolError.wrongPayloadLength(block, expected: payloadLength, actual: payload.count)
        }
    }
}

// The controller stores 0xFF for "set by the display" or "undetermined"; these map it to nil.

func optionalByte(_ byte: UInt8) -> UInt8? {
    byte == 0xFF ? nil : byte
}

func encodeOptional(_ value: UInt8?, field: String) throws -> UInt8 {
    guard let value else { return 0xFF }
    guard value != 0xFF else { throw ProtocolError.invalidValue(field: field, value: Int(value)) }
    return value
}

func decodeEnum<E: RawRepresentable<UInt8>>(_ byte: UInt8, field: String) throws -> E {
    guard let value = E(rawValue: byte) else { throw ProtocolError.unexpectedValue(field: field, value: byte) }
    return value
}

import Foundation

/// Read-only controller identification, returned in reply to `Packet.connect`.
public struct GeneralInfo: Equatable, Sendable {
    public static let minimumPayloadLength = 16

    public var manufacturer: String
    public var model: String
    public var hardwareVersion: String  // e.g. "1.0"
    public var firmwareVersion: String  // e.g. "2.0.0.1"
    public var nominalVoltage: NominalVoltage
    public var maxCurrent: UInt8        // A

    public init(payload: [UInt8]) throws {
        guard payload.count >= Self.minimumPayloadLength else {
            throw ProtocolError.wrongPayloadLength(.general, expected: Self.minimumPayloadLength, actual: payload.count)
        }
        manufacturer = ascii(payload[0..<4])
        model = ascii(payload[4..<8])
        hardwareVersion = payload[8..<10].map { ascii([$0]) }.joined(separator: ".")
        firmwareVersion = payload[10..<14].map { ascii([$0]) }.joined(separator: ".")
        nominalVoltage = NominalVoltage(code: payload[14])
        maxCurrent = payload[15]
    }
}

public enum NominalVoltage: Sendable, CaseIterable {
    case v24, v36, v48, v60, v24to48, v24to60

    /// Codes above 4 are treated as 24-60V, as in the original tool.
    public init(code: UInt8) {
        self = switch code {
        case 0: .v24
        case 1: .v36
        case 2: .v48
        case 3: .v60
        case 4: .v24to48
        default: .v24to60
        }
    }

    public var label: String {
        switch self {
        case .v24: "24V"
        case .v36: "36V"
        case .v48: "48V"
        case .v60: "60V"
        case .v24to48: "24-48V"
        case .v24to60: "24-60V"
        }
    }

    /// Low battery protection values (V) the original tool offers for this controller.
    public var lowBatteryRange: ClosedRange<UInt8> {
        switch self {
        case .v24: 18...22
        case .v36: 28...32
        case .v48: 38...43
        case .v60: 48...55
        case .v24to48: 18...43
        case .v24to60: 18...55
        }
    }
}

private func ascii(_ bytes: some Collection<UInt8>) -> String {
    String(String.UnicodeScalarView(bytes.map(Unicode.Scalar.init)))
        .trimmingCharacters(in: .whitespaces.union(.controlCharacters))
}

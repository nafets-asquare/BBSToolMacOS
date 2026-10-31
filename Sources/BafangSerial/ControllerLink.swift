import BafangProtocol
import Foundation

public enum LinkError: Error, CustomStringConvertible, Sendable {
    /// No complete response arrived in time. `received` holds whatever did arrive.
    case timeout(Expectation, received: [UInt8])
    /// The response could not be framed or decoded.
    case malformed(ProtocolError, received: [UInt8])

    public var description: String {
        switch self {
        case .timeout(let expectation, let received):
            let what = received.isEmpty ? "nothing" : hex(received)
            return "no complete response to \(expectation) (received \(what))"
        case .malformed(let error, let received):
            return "malformed response \(error) (received \(hex(received)))"
        }
    }
}

public enum TraceEvent: Sendable {
    case sent([UInt8])
    case received([UInt8])
    /// Bytes that arrived after a complete response.
    case trailing([UInt8])
}

/// Request/response exchanges with the controller over a serial port. Blocking; call it
/// off the main thread, or use `ControllerSession`, which also verifies writes.
public final class ControllerLink {
    public struct Options: Sendable {
        public var responseTimeout: Duration = .milliseconds(1500)
        /// Writes go to flash, so allow the controller longer to answer.
        public var writeTimeout: Duration = .seconds(3)
        public var connectAttempts = 3
        /// The original tool waited 50-80 ms before each request.
        public var delayBeforeRequest: Duration = .milliseconds(80)
        /// After a complete response, keep listening this long for stray bytes (reported as `.trailing`).
        public var trailingListen: Duration = .milliseconds(150)
        /// Close and reopen the port before each request, as the original tool did.
        /// Off by default; discarding pending input is normally enough.
        public var reopenBetweenRequests = false

        public init() {}
    }

    public let port: SerialPort
    public var options: Options
    public var trace: ((TraceEvent) -> Void)?

    public init(port: SerialPort, options: Options = Options()) {
        self.port = port
        self.options = options
    }

    /// Requests the general info block, retrying a few times like the original tool.
    @discardableResult
    public func connect() throws -> GeneralInfo {
        var lastError: Error?
        for _ in 0..<max(options.connectAttempts, 1) {
            do {
                let response = try readData(request: Packet.connect, block: .general)
                do {
                    return try GeneralInfo(payload: response.payload)
                } catch let error as ProtocolError {
                    throw LinkError.malformed(error, received: response.payload)
                }
            } catch LinkError.timeout(let expectation, let received) {
                lastError = LinkError.timeout(expectation, received: received)
            }
        }
        throw lastError!
    }

    /// Reads and decodes one settings block. The raw response is returned alongside so its
    /// checksum and bytes can be inspected.
    public func read<S: SettingsBlock>(_ type: S.Type) throws -> (settings: S, response: DataResponse) {
        let response = try readData(request: Packet.read(S.block), block: S.block)
        do {
            return (try S(payload: response.payload), response)
        } catch let error as ProtocolError {
            throw LinkError.malformed(error, received: response.payload)
        }
    }

    /// Writes one settings block and returns the controller's verdict. The controller
    /// replies before it is known whether the values were stored as sent; reading the
    /// block back is the only confirmation.
    public func write<S: SettingsBlock>(_ settings: S) throws -> WriteResult {
        let request = try Packet.write(settings)
        let response = try exchange(request, expecting: .writeAck(S.block), timeout: options.writeTimeout)
        guard case .writeAck(_, let code) = response else {
            preconditionFailure("framer returned a response of the wrong kind")
        }
        return S.writeResult(code: code)
    }

    private func readData(request: [UInt8], block: Block) throws -> DataResponse {
        let received = try exchange(request, expecting: .data(block), timeout: options.responseTimeout)
        guard case .data(let response) = received else {
            preconditionFailure("framer returned a response of the wrong kind")
        }
        guard response.checksumMatches else {
            throw LinkError.malformed(
                .checksumMismatch(block, expected: response.expectedChecksum, actual: response.checksum),
                received: [block.rawValue, UInt8(response.payload.count)] + response.payload + [response.checksum]
            )
        }
        return response
    }

    private func exchange(_ request: [UInt8], expecting expectation: Expectation, timeout: Duration) throws -> Response {
        if options.reopenBetweenRequests {
            port.close()
            try port.open()
        } else {
            try port.open()
            port.discardInput()
        }
        Thread.sleep(forTimeInterval: options.delayBeforeRequest.seconds)

        try port.write(request)
        trace?(.sent(request))

        var framer = ResponseFramer()
        var received: [UInt8] = []
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            let chunk = try port.read(timeout: deadline - clock.now)
            guard !chunk.isEmpty else { continue }
            received += chunk
            trace?(.received(chunk))
            framer.append(chunk)

            let response: Response?
            do {
                response = try framer.next(expecting: expectation)
            } catch let error as ProtocolError {
                throw LinkError.malformed(error, received: received)
            }
            if let response {
                listenForTrailingBytes(after: framer.buffer)
                return response
            }
        }
        throw LinkError.timeout(expectation, received: received)
    }

    private func listenForTrailingBytes(after leftover: [UInt8]) {
        var trailing = leftover
        if options.trailingListen > .zero, let more = try? port.read(timeout: options.trailingListen) {
            trailing += more
        }
        if !trailing.isEmpty {
            trace?(.trailing(trailing))
        }
    }
}

public func hex(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

extension Duration {
    var seconds: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}

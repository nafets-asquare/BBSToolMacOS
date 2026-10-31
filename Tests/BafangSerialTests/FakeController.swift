import BafangProtocol
import Darwin
import Foundation

/// Simulates a controller on the master side of a pseudo-terminal. `SerialPort` opens the
/// slave side (`path`) exactly as it would a USB adapter.
final class FakeController: @unchecked Sendable {
    struct Script: Sendable {
        /// Full response bytes per requested block ID. Missing blocks get no reply.
        /// A successful write replaces the block's reply with the written payload.
        var replies: [UInt8: [UInt8]] = [:]
        /// Replies are sent in pieces of this size, with a pause between pieces.
        var chunkSize = 1
        var pauseBetweenChunks: Duration = .milliseconds(2)
        /// Number of connect requests to ignore before answering.
        var ignoredConnects = 0
        /// Write result code to answer per block ID instead of success.
        var writeRejections: [UInt8: UInt8] = [:]
        /// Acknowledge writes as successful without storing them.
        var discardWrites = false
    }

    let path: String
    private let master: Int32
    private let lock = NSLock()
    private var _requests: [[UInt8]] = []
    private var running = true

    /// Every request received so far.
    var requests: [[UInt8]] {
        lock.withLock { _requests }
    }

    init(script: Script) throws {
        master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0, let name = ptsname(master) else {
            throw POSIXError(.ENODEV)
        }
        path = String(cString: name)
        Thread.detachNewThread { [self] in serve(script) }
    }

    deinit {
        stop()
    }

    /// Stops answering and closes the master side, which the port sees as the device going away.
    func stop() {
        let wasRunning = lock.withLock {
            defer { running = false }
            return running
        }
        guard wasRunning else { return }
        Thread.sleep(forTimeInterval: 0.06)
        close(master)
    }

    private var isRunning: Bool {
        lock.withLock { running }
    }

    private func serve(_ script: Script) {
        var script = script
        var pending: [UInt8] = []
        while isRunning {
            var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 20) > 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: 64)
            let count = read(master, &buffer, buffer.count)
            guard count > 0 else { continue }  // EIO while the slave side is closed
            pending += buffer.prefix(count)

            while let request = takeRequest(from: &pending) {
                lock.withLock { _requests.append(request) }
                if request[0] == Opcode.write.rawValue {
                    handleWrite(request, &script)
                } else {
                    handleRead(request, &script)
                }
            }
        }
    }

    private func handleRead(_ request: [UInt8], _ script: inout Script) {
        let block = request[1]
        if block == Block.general.rawValue, script.ignoredConnects > 0 {
            script.ignoredConnects -= 1
            return
        }
        if let reply = script.replies[block] {
            send(reply, script)
        }
    }

    private func handleWrite(_ request: [UInt8], _ script: inout Script) {
        let block = request[1]
        let length = request[2]
        if let code = script.writeRejections[block] {
            send(writeAck(block, code), script)
            return
        }
        if !script.discardWrites, let id = Block(rawValue: block) {
            script.replies[block] = dataResponse(id, Array(request[3..<(3 + Int(length))]))
        }
        send(writeAck(block, length), script)
    }

    /// Block, result code, checksum, as captured from a BBSHD.
    private func writeAck(_ block: UInt8, _ code: UInt8) -> [UInt8] {
        [block, code, Packet.checksum([block, code])]
    }

    /// Reads are `11 <block>`, plus `04 B0 <checksum>` for the general block.
    /// Writes are `16 <block> <length> <payload> <checksum>`.
    private func takeRequest(from pending: inout [UInt8]) -> [UInt8]? {
        let opcodes = [Opcode.read.rawValue, Opcode.write.rawValue]
        guard let start = pending.firstIndex(where: opcodes.contains) else {
            pending.removeAll()
            return nil
        }
        pending.removeFirst(start)

        let length: Int
        if pending[0] == Opcode.write.rawValue {
            guard pending.count >= 3 else { return nil }
            length = 3 + Int(pending[2]) + 1
        } else {
            guard pending.count >= 2 else { return nil }
            length = pending[1] == Block.general.rawValue ? 5 : 2
        }
        guard pending.count >= length else { return nil }
        defer { pending.removeFirst(length) }
        return Array(pending.prefix(length))
    }

    private func send(_ reply: [UInt8], _ script: Script) {
        var offset = 0
        while offset < reply.count {
            let chunk = Array(reply[offset..<min(offset + script.chunkSize, reply.count)])
            _ = write(master, chunk, chunk.count)
            offset += chunk.count
            Thread.sleep(forTimeInterval: Double(script.pauseBetweenChunks.components.attoseconds) / 1e18)
        }
    }
}

/// A read response: block, length, payload, checksum over block + length + payload.
func dataResponse(_ block: Block, _ payload: [UInt8]) -> [UInt8] {
    let body = [block.rawValue, UInt8(payload.count)] + payload
    return body + [Packet.checksum(body)]
}

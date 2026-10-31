import BafangProtocol
import Darwin
import Foundation

/// Simulates a controller on the master side of a pseudo-terminal. `SerialPort` opens the
/// slave side (`path`) exactly as it would a USB adapter.
final class FakeController: @unchecked Sendable {
    struct Script: Sendable {
        /// Full response bytes per requested block ID. Missing blocks get no reply.
        var replies: [UInt8: [UInt8]] = [:]
        /// Replies are sent in pieces of this size, with a pause between pieces.
        var chunkSize = 1
        var pauseBetweenChunks: Duration = .milliseconds(2)
        /// Number of connect requests to ignore before answering.
        var ignoredConnects = 0
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

    func stop() {
        lock.withLock { running = false }
        Thread.sleep(forTimeInterval: 0.06)
        close(master)
    }

    private var isRunning: Bool {
        lock.withLock { running }
    }

    private func serve(_ script: Script) {
        var pending: [UInt8] = []
        var ignoredConnects = script.ignoredConnects
        while isRunning {
            var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 20) > 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: 64)
            let count = read(master, &buffer, buffer.count)
            guard count > 0 else { continue }  // EIO while the slave side is closed
            pending += buffer.prefix(count)

            while let request = takeRequest(from: &pending) {
                lock.withLock { _requests.append(request) }
                let block = request[1]
                if block == Block.general.rawValue, ignoredConnects > 0 {
                    ignoredConnects -= 1
                    continue
                }
                if let reply = script.replies[block] {
                    send(reply, script)
                }
            }
        }
    }

    /// Read requests are `11 <block>`, plus `04 B0 <checksum>` for the general block.
    private func takeRequest(from pending: inout [UInt8]) -> [UInt8]? {
        guard let start = pending.firstIndex(of: Opcode.read.rawValue) else {
            pending.removeAll()
            return nil
        }
        pending.removeFirst(start)
        guard pending.count >= 2 else { return nil }
        let length = pending[1] == Block.general.rawValue ? 5 : 2
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

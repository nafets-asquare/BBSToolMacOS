import Darwin
import Foundation

public struct SerialError: Error, CustomStringConvertible, Sendable {
    public var operation: String
    public var path: String
    public var code: Int32

    init(_ operation: String, path: String, code: Int32 = errno) {
        self.operation = operation
        self.path = path
        self.code = code
    }

    public var description: String {
        "\(operation) \(path): \(String(cString: strerror(code)))"
    }
}

// Function-like ioctl macros from <sys/ttycom.h> are not imported into Swift.
private let TIOCEXCL: UInt = 0x2000_740D
private let TIOCMBIS: UInt = 0x8004_746C
private let TIOCM_DTR: Int32 = 0x2
private let TIOCM_RTS: Int32 = 0x4

/// A serial port in raw mode: 8N1, no flow control, DTR and RTS asserted.
///
/// The original tool enabled XON/XOFF, which is unsafe for this binary protocol
/// (0x11 is the read opcode and also XON); it is off here.
public final class SerialPort {
    public let path: String
    public let baudRate: speed_t
    private var fd: Int32 = -1

    public init(path: String, baudRate: speed_t = 1200) {
        self.path = path
        self.baudRate = baudRate
    }

    deinit {
        close()
    }

    public var isOpen: Bool { fd >= 0 }

    public func open() throws {
        guard !isOpen else { return }
        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw SerialError("open", path: path) }

        do {
            guard ioctl(fd, TIOCEXCL) == 0 else { throw SerialError("lock", path: path) }

            var options = termios()
            guard tcgetattr(fd, &options) == 0 else { throw SerialError("read settings of", path: path) }
            cfmakeraw(&options)
            options.c_cflag |= tcflag_t(CLOCAL | CREAD | CS8)
            options.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CRTSCTS)
            options.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
            cfsetspeed(&options, baudRate)
            guard tcsetattr(fd, TCSANOW, &options) == 0 else { throw SerialError("configure", path: path) }
        } catch {
            Darwin.close(fd)
            throw error
        }

        // Not every device supports modem lines (pseudo-terminals don't), so this is best effort
        var lines = TIOCM_DTR | TIOCM_RTS
        _ = ioctl(fd, TIOCMBIS, &lines)

        tcflush(fd, TCIOFLUSH)
        self.fd = fd
    }

    public func close() {
        guard isOpen else { return }
        Darwin.close(fd)
        fd = -1
    }

    /// Discards bytes received but not yet read.
    public func discardInput() {
        guard isOpen else { return }
        tcflush(fd, TCIFLUSH)
    }

    /// Writes all bytes and waits until they have been transmitted.
    public func write(_ bytes: [UInt8]) throws {
        guard isOpen else { throw SerialError("write to", path: path, code: EBADF) }
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written < 0 {
                guard errno == EAGAIN || errno == EINTR else { throw SerialError("write to", path: path) }
                try waitFor(Int16(POLLOUT), timeout: .seconds(1))
                continue
            }
            offset += written
        }
        guard tcdrain(fd) == 0 else { throw SerialError("drain", path: path) }
    }

    /// Returns the bytes available within the timeout; empty if none arrived.
    public func read(timeout: Duration) throws -> [UInt8] {
        guard isOpen else { throw SerialError("read from", path: path, code: EBADF) }
        guard try waitFor(Int16(POLLIN), timeout: timeout) else { return [] }
        var buffer = [UInt8](repeating: 0, count: 256)
        let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        if count < 0 {
            guard errno == EAGAIN || errno == EINTR else { throw SerialError("read from", path: path) }
            return []
        }
        if count == 0 {
            // End of file: the device went away (e.g. the cable was unplugged)
            throw SerialError("read from", path: path, code: ENXIO)
        }
        return Array(buffer.prefix(count))
    }

    @discardableResult
    private func waitFor(_ events: Int16, timeout: Duration) throws -> Bool {
        var descriptor = pollfd(fd: fd, events: events, revents: 0)
        let result = poll(&descriptor, 1, Int32(timeout.milliseconds))
        if result < 0 {
            guard errno == EINTR else { throw SerialError("wait for", path: path) }
            return false
        }
        if descriptor.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0, descriptor.revents & events == 0 {
            throw SerialError("wait for", path: path, code: ENXIO)
        }
        return result > 0
    }
}

extension Duration {
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}

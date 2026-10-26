import Foundation
import Darwin

public enum LocalIPC {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/GimmeRemote")
    }
    public static var path: String { directory.appendingPathComponent("control.sock").path }

    public static func address() throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw ControlError("ipcPathTooLong") }
        withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
    public static func withAddress<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> T) throws -> T {
        var address = try address()
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
    public static func setTimeout(_ fd: Int32) {
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }
    public static func readLine(_ fd: Int32) throws -> String {
        var bytes: [UInt8] = []
        var byte: UInt8 = 0
        while bytes.count < 4096 {
            guard Darwin.read(fd, &byte, 1) == 1 else { throw ControlError("ipcDisconnected") }
            if byte == 10 { return String(decoding: bytes, as: UTF8.self) }
            bytes.append(byte)
        }
        throw ControlError("messageTooLarge")
    }
    public static func writeLine(_ text: String, fd: Int32) throws {
        let data = Array((text + "\n").utf8)
        try data.withUnsafeBytes { pointer in
            var offset = 0
            while offset < data.count {
                let written = Darwin.write(fd, pointer.baseAddress!.advanced(by: offset), data.count - offset)
                guard written > 0 else { throw ControlError("ipcDisconnected") }
                offset += written
            }
        }
    }
    public static func request(_ command: String) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlError("ipcUnavailable") }
        defer { Darwin.close(fd) }
        setTimeout(fd)
        guard try withAddress({ Darwin.connect(fd, $0, $1) }) == 0 else { throw ControlError("appNotRunning") }
        try writeLine(command, fd: fd)
        return try readLine(fd)
    }
}

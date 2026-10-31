import Foundation
import Darwin
import RemoteCore

/// Same-user Unix socket only; no control API is exposed over HTTP.
final class IPCServer: @unchecked Sendable {
    private let fd: Int32
    init(handler: @escaping @MainActor @Sendable (String) async -> String) throws {
        try FileManager.default.createDirectory(at: LocalIPC.directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        chmod(LocalIPC.directory.path, 0o700)
        unlink(LocalIPC.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlError("ipcUnavailable") }
        self.fd = fd
        guard try LocalIPC.withAddress({ Darwin.bind(fd, $0, $1) }) == 0, listen(fd, 4) == 0 else {
            Darwin.close(fd)
            throw ControlError("ipcUnavailable")
        }
        chmod(LocalIPC.path, 0o600)
        DispatchQueue(label: "com.lucientong.GimmeRemote.ipc").async {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                LocalIPC.setTimeout(client)
                do {
                    let command = try LocalIPC.readLine(client)
                    guard ["status", "pair", "stop", "resume"].contains(command) else {
                        try LocalIPC.writeLine("Unknown command", fd: client)
                        Darwin.close(client)
                        continue
                    }
                    // This serial worker owns the descriptor until the response completes.
                    let completion = DispatchSemaphore(value: 0)
                    Task { @MainActor in
                        let response = await handler(command)
                        try? LocalIPC.writeLine(response, fd: client)
                        completion.signal()
                    }
                    completion.wait()
                } catch {}
                Darwin.close(client)
            }
        }
    }
    deinit { Darwin.close(fd); unlink(LocalIPC.path) }
}

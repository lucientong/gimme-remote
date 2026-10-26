import Foundation
import SystemConfiguration

public enum NetworkAddress {
    public static let port = 9271
    static func hosts() -> [String] {
        var hosts = ["localhost", "127.0.0.1"]
        if let name = SCDynamicStoreCopyLocalHostName(nil) as String? { hosts.insert("\(name).local", at: 0) }
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&interfaces) == 0 {
            defer { freeifaddrs(interfaces) }
            var current = interfaces
            while let interface = current?.pointee {
                defer { current = interface.ifa_next }
                guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                      (interface.ifa_flags & UInt32(IFF_UP)) != 0,
                      (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    hosts.append(String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self))
                }
            }
        }
        return hosts
    }
    static func origins(port: Int = port) -> Set<String> { Set(hosts().map { "http://\($0.lowercased()):\(port)" }) }
    public static func accessURLs() -> [String] {
        hosts().filter { $0 != "localhost" && $0 != "127.0.0.1" }.map { "http://\($0):\(port)" }
    }
    public static func preferredURL() -> String { "http://\(hosts().first!):\(port)" }
}

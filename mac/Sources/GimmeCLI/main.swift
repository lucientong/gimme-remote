import Foundation
import RemoteCore

let args = Array(CommandLine.arguments.dropFirst())
if args == ["--version"] {
    print("gimme \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
} else if args.count == 1, ["status", "pair", "stop"].contains(args[0]) {
    do { print(try LocalIPC.request(args[0])) }
    catch {
        fputs("gimme: \((error as? ControlError)?.code ?? "requestFailed"). Open GimmeRemote.app first.\n", stderr)
        exit(1)
    }
} else {
    print("Usage: gimme status | pair | stop | --version\nControls the local Gimme Remote menu bar app.")
    if !args.isEmpty && args != ["--help"] { exit(2) }
}

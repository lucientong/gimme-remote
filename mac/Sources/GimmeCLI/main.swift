import Foundation
import RemoteCore

/// Homebrew links the CLI out of the App bundle; resolve the link to read the App's Info.plist.
func appVersion() -> String {
    let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return Bundle(url: app)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
}

let args = Array(CommandLine.arguments.dropFirst())
if args == ["--version"] {
    print("gimme \(appVersion())")
} else if args.count == 1, ["status", "pair", "stop", "resume"].contains(args[0]) {
    do { print(try LocalIPC.request(args[0])) }
    catch {
        fputs("gimme: \((error as? ControlError)?.code ?? "requestFailed"). Open GimmeRemote.app first.\n", stderr)
        exit(1)
    }
} else {
    print("Usage: gimme status | pair | stop | resume | --version\nControls the local Gimme Remote menu bar app.")
    if !args.isEmpty && args != ["--help"] { exit(2) }
}

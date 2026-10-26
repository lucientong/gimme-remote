# gimme-remote

**English** | [简体中文](README.zh-CN.md)

**Gimme the remote.** Connect your Mac to a TV and use your phone as the remote. A native Swift menu bar app serves a mobile web interface on your local network. No iOS app required.

The first release implements media controls, a touchpad, Chinese text input, IINA and browser shortcuts, QR code pairing, Keychain tokens, permission guidance, lock screen status, reconnection, launch at login, sleep prevention, and the local `gimme` CLI. Screenshot-based clicking is a planned optional enhancement.

## Installation

Once the first stable release is published and synced to the Homebrew tap:

```bash
brew tap lucientong/tap
brew install --cask lucientong/tap/gimme-remote
open -a GimmeRemote
```

Open the menu bar app and grant Accessibility permission. Connect your phone and Mac to the same Wi-Fi network, scan the QR code, and enter the pairing code to connect. In Safari, use **Share → Add to Home Screen** to save the remote.

Volume buttons adjust **player volume**; use your TV remote to adjust the TV's overall volume. Web player shortcuts depend on page focus and website support. You can always use the touchpad to click controls on the TV display. The app does not use a Service Worker, cloud relay, or arbitrary script execution.

Requires macOS 14 or later. Releases are universal apps for Apple Silicon and Intel, distributed through GitHub Releases with free ad-hoc signing. They are not notarized by Apple.

If macOS blocks the first launch, open **System Settings → Privacy & Security → Open Anyway** for GimmeRemote. Grant Accessibility permission for remote input. After an update, macOS may require granting that permission again.

## Development

Requires Swift 6.2+ and Node 22.12+. The full native test suite requires Xcode. Command Line Tools can build the app and run the core security checks.

```bash
npm --prefix web ci
npm --prefix web test
npm --prefix web run build
swift build --package-path mac --jobs 4 --disable-index-store
bash scripts/test-core.sh
swift run --package-path mac --jobs 4 --disable-index-store TransportChecks

# With a full Xcode installation
swift test --package-path mac --jobs 4
```

`TransportChecks` verifies real HTTP/WebSocket behavior using temporary pages and in-memory tokens. It does not access your personal Keychain or inject system input.

Open `mac/Package.swift` in Xcode to debug the native app. Keep the Bundle ID `com.lucientong.GimmeRemote` consistent. Verify installation, input permissions, and launch at login using the app bundle produced by `scripts/build-release.sh`; a standalone Swift Package Manager executable is not an installed app.

Run the frontend independently with hot reload:

```bash
npm --prefix web run dev
```

The app listens on port `9271` by default. Vite proxies `/ws` to `127.0.0.1:9271`. Set these environment variables when running the native app during development:

```text
GIMME_WEB_ROOT=/absolute/path/to/gimme-remote/web/dist
GIMME_DEV_ORIGINS=http://localhost:5173,http://192.168.1.2:5173
```

Replace the second origin with the actual local IP address of the Mac running Vite. Development origins must be explicitly allowlisted. Use the Mac's IP address to access Vite from your phone. You can also set `VITE_REMOTE_URL=http://mac.local:9271` to connect directly to the native service, but the Vite page's origin must still be allowlisted.

Release builds copy `web/dist` into `GimmeRemote.app/Contents/Resources/Web`. The page and WebSocket share the same origin, and Node is not required in production. The menu bar updates the host address when the network changes. A page at a new local IP address may require pairing again; prefer saving the stable `.local` address.

## CLI

```bash
gimme status   # Show service status, permissions, connections, and access URLs
gimme pair     # Generate a new one-time pairing code and print access URLs
gimme stop     # Pause remote input; resume from the menu bar
```

The CLI communicates through a Unix socket in a private directory for the current user. The menu bar supports pausing input, disconnecting devices, revoking all pairings, launch at login, and preventing sleep while connected.

## Releases

Pull requests run checks. Pushes to `master`, including merged pull requests, publish a `testing` prerelease after checks pass. Tags matching `vMAJOR.MINOR.PATCH` publish stable releases and update the Homebrew tap. Tags with a prerelease suffix publish prereleases without updating the stable Cask.

Builds use ad-hoc signing and do not require an Apple Developer membership or Apple secrets. The only custom repository secret is `HOMEBREW_TAP_TOKEN` in `lucientong/gimme-remote`: a fine-grained GitHub PAT granting **Contents: Read and write** to **only `lucientong/homebrew-tap`**. GitHub provides the release publishing token automatically.

To build a release locally on macOS:

```bash
bash scripts/build-release.sh
```

The default build produces a universal `GimmeRemote.app`, ZIP, and `SHA256SUMS` under `build/`. Set `GIMME_OUTPUT_DIR` to a fresh directory for later builds; the script refuses to replace an existing app. Use `--unsigned` only to validate bundle packaging without producing a release ZIP.

## Project Structure

```text
mac/        Native Swift app, server, input handling, CLI, and core tests
web/        Mobile interface built with Preact / TypeScript / Vite
shared/     Protocol JSON Schema
scripts/    Builds, core checks, and Homebrew Cask generation
```

Browser, iPhone, HDMI display, and system permission behavior require manual testing on real devices. Automated tests do not cover every player scenario.

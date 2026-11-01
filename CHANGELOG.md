# Changelog

## 8.0.0

- Support Capacitor 8 and Swift Package Manager while retaining Capacitor 7 and CocoaPods integration.
- Replace the unmaintained iOS SwiftSocket dependency with Apple Network.framework.
- Add native TCP server APIs on iOS and Android: `listen`, `accept`, and `closeServer`. Accepted clients use the existing send/read/disconnect APIs.
- Serialize iOS reads and preserve buffered data across short reads and timeouts. Preserve sending after a peer half-close.
- Keep existing client API signatures, encodings, default port, iOS empty-send/odd-hex behavior, empty EOF/native-read-error results, nonblocking reads for nonpositive timeouts, and idempotent disconnect. Add opt-in `rejectOnEOF` without changing platform defaults.
- Fix the example's Scene lifecycle startup on current iOS; include native, browser, simulator and physical-device TCP regression coverage.

### Integration notes

- The Capacitor 8 example requires Node 22+, JDK 21 and Xcode 26+. Swift Package Manager requires iOS 15+. Host applications must meet their Capacitor version's requirements.
- LAN access requires the host's local-network usage description, user permission and a reachable server address. A phone's localhost is not the development Mac.
- TCP reads may be short; they do not define message boundaries. iOS read timeout zero/negative polls; Android timeout zero waits indefinitely. Server accept timeout zero waits indefinitely on both platforms.
- Invalid iOS ports and nonpositive read lengths now reject instead of reaching the old socket implementation. Error message text is not a stable API.
- Browser TCP remains unsupported. Server APIs do not grant background execution privileges.
- Physical-device verification covers iPhone 16 Pro / iOS 27.0.1. The original causes of sparse historical reports #1/#4 remain unconfirmed; see ISSUE_RESOLUTION.md and MACOS_VALIDATION.md for evidence and limits.

# Changelog

## 8.0.0

### Features and fixes

- Capacitor 8 and Swift Package Manager support; retain Capacitor 7 and CocoaPods integration.
- Replace iOS SwiftSocket with Apple Network.framework; fix current-iOS example Scene startup.
- Add native TCP servers through listen/accept/closeServer.
- Use one validated runtime contract for both native platforms with stable error codes.
- Move Android connect/DNS off the Capacitor thread and apply an explicit connection deadline.
- Serialize reads and writes independently, preserve bytes after read timeouts, and support half-close sending.
- Release disconnected sockets and clean up active/pending operations when the plugin is destroyed.
- Bound individual receive buffers without limiting total transfer size; guard numeric overflow and malformed encodings.
- Remove browser payload logging and unify unsupported errors.
- Add shared real native contract tests, lifecycle tests and migration documentation.

### Breaking changes

- Read timeout rejects TIMEOUT; EOF rejects EOF on both platforms. Local closure rejects CLOSED.
- Timeout zero waits indefinitely on both platforms; negative/fractional/nonfinite options reject INVALID_ARGUMENT.
- Empty sends succeed; odd Hex and malformed/noncanonical Base64 reject.
- Invalid UTF-8 falls back to Base64 on Android as well as iOS; encoding labels are exact lowercase values.
- Closed/unknown handles and simultaneous accepts use defined error codes; repeated close is idempotent.

See [MIGRATION_V8.md](MIGRATION_V8.md) for the complete behavior table and migration examples.
Host apps must meet their Capacitor version's platform requirements; SPM requires iOS 15+.

# V8 contract and review

Status: unified implementation completed and locally validated on 2026-11-01; expanded remote CI is pending. Release remains paused during this review. The earlier compatibility-first candidate is superseded; main and npm have not been updated.

## Agreed contract

- Both platforms: EOF rejects `EOF`; read/accept/connect timeout rejects `TIMEOUT`; timeout zero waits indefinitely. Negative/fractional/nonfinite timeout values reject `INVALID_ARGUMENT`.
- Empty sends succeed without changing the connection. Hex must contain complete bytes; malformed Hex/Base64 and unknown encodings reject `INVALID_ARGUMENT`.
- Invalid UTF-8 falls back to Base64 with the returned encoding identifying the result. Binary protocols should select Hex/Base64 explicitly.
- Client reads and writes each execute in invocation order; reads and writes can progress independently. Timeout is measured when an operation starts, not while queued.
- Disconnect and closeServer are idempotent for previously issued IDs; unknown IDs reject `INVALID_ARGUMENT`. Operations on a closed issued handle reject `CLOSED`.
- Closing a client interrupts pending I/O. Closing a listener rejects pending accepts but preserves accepted clients. Destroying the plugin closes owned connections/listeners and settles pending calls.
- Stable error codes: `INVALID_ARGUMENT`, `TIMEOUT`, `EOF`, `CLOSED`, `BUSY`, `CONNECT_FAILED`, `LISTEN_FAILED`, `IO_ERROR`, `UNIMPLEMENTED`. OS-specific message text is diagnostic only.
- TCP remains a byte stream, not framed messages. No promise of OS-identical packet boundaries, DNS timing, permissions or background execution.

## Findings addressed

1. Platform-specific EOF, zero timeout, empty send, odd Hex and invalid UTF-8 behavior.
2. Android connect blocks the Capacitor plugin thread, delaying unrelated operations.
3. Invalid Android port, read length, timeout and Base64 can throw uncaught exceptions.
4. Android concurrent reads compete for bytes and socket timeout configuration; concurrent writes can interleave.
5. Android retains disconnected Socket objects and re-reads mutable client lists from worker threads during destruction.
6. Missing stable native error codes and distinctions between local close, remote EOF and read timeout.
7. Pending connection/listener lifecycle and queued accept resource ownership need explicit cleanup.
8. Browser client methods log payloads and use a different unsupported error path from server methods.
9. Public argument validation and documentation need one shared contract, including optional/default values and malformed encodings.
10. Tests must cover failure paths, concurrent operations, cancellation, large payloads, listener restart and the same cross-platform behavior, not just successful echo.
11. iOS Network.framework can put a refused connection into waiting rather than failed; refuse immediately with CONNECT_FAILED instead of misreporting an elapsed timeout.
12. Remote Android CI lacked permission to use KVM and failed to install the APK because the package service was unavailable (0 tests executed). Added the action's documented KVM setup and require hardware acceleration; a new run must confirm the outcome.

Resource allocation should follow actual requested data, with bounded read chunks rather than allocating expectLen bytes blindly. No arbitrary business limits on valid payload sizes will be introduced merely for convenience.

TLS, UDP, automatic reconnection and background execution are separate capabilities, not fixes to this TCP API. They are outside this release's defect-correction scope.

## Implementation and evidence

- Shared TypeScript boundary validates runtime input before either native bridge: invalid shapes, types, ranges, encodings and binary representations reject INVALID_ARGUMENT. Native code also guards decoding and allocations. Five contract test groups include malformed inputs and no browser payload logging.
- Android uses live-client maps, independent serial read/write workers with idle thread expiry, background connection/DNS plus a deadline, and tracked pending connects/listens. Destroy interrupts sockets and settles pending calls. Pending-listen removal is atomic to avoid duplicate callbacks during a failure/destroy race.
- iOS keeps one serial owner per connection, FIFO reads/writes, a bounded receive chunk, EOF distinct from local closure, and cleanup of connecting/listening/accepting state without retaining the plugin indefinitely.
- SPM and CocoaPods native Swift suites: 9 tests each passed, including refusal classification, timeout recovery, half-close, queued cancellation and plugin deinitialization.
- Android API 37 emulator: 3 instrumentation tests passed, including the full JS/native/socket contract and actual plugin destruction with pending reads/accept.
- The same full contract suite passed in iOS 26.5 simulator examples using Capacitor 8 CocoaPods, actual npm-package SPM, and actual npm-package Capacitor 7.6.10 CocoaPods.
- iPhone 16 Pro / iOS 27.0.1: user triggered the updated example; GUI success confirmed at 21:27:18, native trace verified, and Mac TCP server recorded receipt after half-close. Tests include 256 KiB binary transfer, invalid inputs, FIFO I/O, timeout zero, stable errors, listener restart and repeated closure.
- Browser integration: 2 tests passed. Build, ESLint and npm-package layout checks passed. Logs are in `validation/2026-11-01/v8-unified-*`.

Known limits: this is evidence for the tested devices/runtimes, not proof of every network or device. OS DNS timing and background suspension are not unified. The Capacitor 7/Xcode 27 fixture required an iOS 15 deployment override; iOS 14 was not runtime-tested. Historical failures remain in the earlier records. Breaking changes and migration code are in MIGRATION_V8.md.

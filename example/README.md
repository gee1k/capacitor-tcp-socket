# TCP Socket example

This app imports the local plugin through `file:../` and runs Capacitor 8.
Use Node 22+ and JDK 21 for Android; iOS requires macOS and Xcode 26+.

```sh
# Repository root
npm ci
npm run build
cd example
npm ci
npm run build
npx cap sync android
npx cap run android
```

For iOS with the checked-in CocoaPods project, use `npx cap sync ios` and
`npx cap run ios`. The example includes `NSLocalNetworkUsageDescription`.
Allow local network access on the device, and use the server machine's LAN IP;
`127.0.0.1` on a phone points to the phone, not your computer.

## Real native TCP smoke test

On the server computer, run `npm run test:server` from this directory. It binds
port 9100. In the native example, enter its reachable IP and port and press
**Run TCP smoke test**. Android emulator uses `10.0.2.2` to reach its host;
an iOS simulator can use `127.0.0.1`. For USB Android, `adb reverse tcp:9100
tcp:9100` also allows the default loopback address.

The action runs the same native V8 contract suite on both platforms: invalid
arguments/encodings, empty sends, timeout/EOF/CLOSED/BUSY codes, UTF-8 fallback,
FIFO concurrent reads/writes, indefinite read cancellation, 256 KiB binary
transfer, listener restart, repeated close, and accepted-client survival after
listener close. It then verifies real host TCP UTF-8/Hex/Base64 exchanges, short
reads, timeout recovery, peer EOF and sending after peer half-close.

No WebSocket replacement or socket mock is used. The test server recognizes
DELAY\n (3 second delay), CLOSE\n (peer half-close), and AFTER_EOF\n (verifies
that receiving EOF did not disable sending). TIMEOUT and EOF are expected rejected
Promises in V8, not successful empty strings.

An Android instrumentation test launches this same packaged example, starts a
real loopback TCP server on the emulator/device, and presses the smoke button.
A separate lifecycle test destroys the actual plugin with read/accept calls
pending and checks that all settle as CLOSED:

```sh
# Build/sync first, then with a connected emulator/device:
cd android
bash ./gradlew :app:connectedDebugAndroidTest
```

To verify SPM integration without changing the checked-in CocoaPods example,
run `npm run test:spm`. It creates a temporary example using the same local
plugin, adds iOS with SPM and syncs. On macOS it also builds the simulator app;
on Linux it explicitly reports that compilation remains unverified. The macOS
CI job builds both CocoaPods and SPM examples and runs native Swift socket tests.

## Browser integration tests

```sh
npx playwright install chromium
npm run test:browser
# Or use an existing Chromium installation:
CHROMIUM_PATH=/usr/bin/chromium npm run test:browser
```

Browser tests load the actual app and local plugin and assert the unsupported
TCP error, disconnected state and absence of uncaught page errors. They do not
validate native TCP. `npm start` runs the browser example for manual inspection.

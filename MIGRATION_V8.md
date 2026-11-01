# Migrating from v7 to v8

V8 supports Capacitor 7/8, CocoaPods/SPM, and keeps connect/send/read/disconnect.
It replaces SwiftSocket with Network.framework and adds native listen/accept/closeServer.
It intentionally corrects old platform inconsistencies rather than preserving them.

## Breaking behavior changes

| Area | v7 / earlier behavior | V8 on both platforms | Migration |
| --- | --- | --- | --- |
| Read timeout | Empty success result | Rejects TIMEOUT | Catch TIMEOUT for an idle interval |
| Peer EOF | iOS empty result; Android EOF | Rejects EOF | End the receive loop on EOF |
| Native read errors | iOS could hide failures as empty results | IO_ERROR or CLOSED | Handle errors instead of treating them as idle |
| Read timeout 0 | iOS polling, Android indefinite | Indefinite | Use positive timeout for periodic waiting; disconnect to cancel |
| Invalid numbers | Could truncate, hang or crash | INVALID_ARGUMENT | Pass whole nonnegative timeouts and positive read lengths |
| Odd Hex | iOS accepted a final half-byte | Rejected | Supply two digits per byte, e.g. 0f instead of f |
| Empty sends | Android rejected | Successful no-op | Remove platform-specific workarounds |
| Invalid UTF-8 | Android silently replaced bytes | Base64 fallback with actual encoding | Check result.encoding or request binary explicitly |
| Encodings | Android accepted unknown/case-insensitive labels | Exactly utf8, hex or base64 | Use DataEncoding constants |
| Base64 | Android accepted some noncanonical inputs | Canonical standard Base64 | Encode with a standard encoder; include required padding |
| Closed handle read/send | Platform-specific/empty outcomes | CLOSED | Stop using closed handles |
| Repeated close | Platform-specific failures | Idempotent for issued IDs | Safe to close in finally blocks |
| Concurrent reads/writes | Could compete/interleave on Android | Each direction is FIFO per client | A queued read's timeout starts when it becomes active |

Hex accepts whitespace and one leading 0x prefix; output is lowercase Hex.
Numeric options must be finite integers. Timeout range is 0..2147483 seconds;
read length is 1..2147483647, with at most 65536 bytes returned per read. These
bounds prevent overflow/oversized allocation; they do not limit total transfer size.
Socket IDs belong to one plugin instance and must not be persisted across reloads.

## Receive-loop migration

```typescript
import { TcpSocket, DataEncoding, TcpSocketError } from 'capacitor-tcp-socket';

try {
  for (;;) {
    try {
      const chunk = await TcpSocket.read({ client, expectLen: 65536, timeout: 10,
        encoding: DataEncoding.BASE64 });
      // Append decoded bytes to your protocol parser. TCP is not message-framed.
    } catch (cause) {
      const error = cause as TcpSocketError;
      if (error.code === 'TIMEOUT') continue; // idle interval, connection still usable
      if (error.code === 'EOF') break;       // peer finished sending
      throw error;
    }
  }
} finally {
  await TcpSocket.disconnect({ client });
}
```

For indefinite waiting, use timeout: 0 and cancel from another task with disconnect.
Do not spin on empty results. EOF does not itself prevent sending on a half-open
TCP connection. Do not assume one send maps to one read or decode arbitrary binary
as UTF-8. A split UTF-8 character can trigger Base64 fallback; byte accumulation
or a streaming decoder belongs in the application's protocol layer.

No TLS, UDP, automatic reconnection or mobile background execution guarantee is
introduced. Network errors and device permission prompts still depend on the OS.
EOF/CLOSED/TIMEOUT codes are stable; diagnostic message text is not.

# capacitor-tcp-socket

Native TCP byte-stream clients and servers for Capacitor on iOS and Android.
Thanks to [@ottimis](https://www.npmjs.com/package/@ottimis/tcp-socket).

## Installation

```sh
npm install capacitor-tcp-socket@^8
npx cap sync
```

Supports Capacitor 7 and 8, CocoaPods and Swift Package Manager. The example
uses Capacitor 8 (Node 22+, JDK 21, Android SDK 36, Xcode 26+). SPM requires iOS 15+.
Host applications must also meet their Capacitor version's platform requirements.
For a new SPM app: `npx cap add ios --packagemanager SPM`, then `npx cap sync ios`.
The Swift package product is `CapacitorTcpSocket`. The iOS implementation uses
Apple Network.framework.

## Socket behavior

| Operation or condition | Behavior |
| --- | --- |
| Read/accept/connect timeout | Rejects with `TIMEOUT`; default 10 whole seconds |
| Timeout zero | Waits indefinitely; negative/fractional/nonfinite values are invalid |
| Peer finishes sending | Read rejects `EOF`; sending can continue if the peer still receives |
| Local disconnect | Pending I/O and later send/read reject `CLOSED` |
| Empty send | Successful no-op on an open client |
| Hex | Complete bytes only; whitespace and one leading 0x prefix are accepted |
| Base64 | Canonical standard padded Base64; malformed data is rejected |
| Invalid UTF-8 on read | Base64 result with `encoding: 'base64'` |
| Concurrent operations | FIFO reads and FIFO writes per client; the two directions progress independently |
| Closing issued handles | disconnect/closeServer are idempotent; unknown handles reject `INVALID_ARGUMENT` |
| Browser | All TCP methods reject `UNIMPLEMENTED`; payloads are not logged by the plugin |

`read` returns **up to** expectLen bytes (default 1024, at most 64 KiB per result),
not a complete application message. Call it repeatedly and assemble your protocol's
frames. A successful read contains data; EOF and timeout are errors, never empty
success results. Queued read timeouts start when that read begins. Use a positive
timeout for periodic waiting; use disconnect to cancel an indefinite read.

Network routes, DNS, OS diagnostics, local-network permissions and background
execution depend on the operating system. TCP packet boundaries and scheduling
may vary between devices. For arbitrary binary data, use Hex
or Base64. Even valid UTF-8 text may be split inside a multibyte character by TCP;
assemble bytes and use a streaming decoder if your protocol requires streaming text.

## Client usage

```typescript
import { TcpSocket, DataEncoding } from 'capacitor-tcp-socket';

const { client } = await TcpSocket.connect({
  ipAddress: '192.168.1.100', port: 9100, timeout: 10,
});
try {
  await TcpSocket.send({ client, data: 'Hello', encoding: DataEncoding.UTF8 });
  // One chunk, not necessarily a whole response. Frame/assemble as required.
  const chunk = await TcpSocket.read({ client, expectLen: 4096, timeout: 10,
    encoding: DataEncoding.BASE64 });
  const bytes = Uint8Array.from(atob(chunk.result), c => c.charCodeAt(0));
  // Process bytes according to the application's protocol.
} finally {
  await TcpSocket.disconnect({ client });
}
```

## Server usage

```typescript
import { TcpSocket } from 'capacitor-tcp-socket';

const { server, port } = await TcpSocket.listen({ ipAddress: '127.0.0.1', port: 0 });
try {
  const { client } = await TcpSocket.accept({ server, timeout: 10 });
  try {
    await TcpSocket.send({ client, data: 'hello from server' });
  } finally {
    await TcpSocket.disconnect({ client });
  }
} finally {
  await TcpSocket.closeServer({ server });
}
```

Listening defaults to loopback and an OS-assigned port. Use `0.0.0.0` explicitly
for LAN clients. Only one accept may be pending per server (`BUSY` otherwise).
Closing a listener rejects pending accepts with `CLOSED` and preserves accepted
clients. Pending unaccepted connections are bounded by listener backlog; excess
connections may be refused by the OS. Plugin destruction closes owned sockets.

For iOS LAN access, add `NSLocalNetworkUsageDescription` to the host Info.plist
and grant local-network access. Bonjour declarations are only needed for actual
Bonjour browsing/advertising. A phone's localhost is not the development Mac.
Android's INTERNET permission is included by manifest merging.

## Errors

Use `error.code`, not OS-dependent message text:

| Code | Meaning |
| --- | --- |
| INVALID_ARGUMENT | Invalid options, encoding, data representation or unknown handle |
| TIMEOUT | Connect, read or accept deadline elapsed |
| EOF | Peer ended its sending direction |
| CLOSED | Client/listener/plugin was closed locally |
| BUSY | An accept is already pending on this listener |
| CONNECT_FAILED | Connection establishment failed |
| LISTEN_FAILED | Binding/listening failed |
| IO_ERROR | Other established-connection or accept failure |
| UNIMPLEMENTED | Raw TCP is unavailable in browsers |

## Example and verification

See [example/README.md](example/README.md) for real device/simulator TCP tests.
`npm test` checks the shared runtime input contract; `npm run build` builds the
package and API docs. Native tests exercise real sockets, concurrency, cancellation,
encoding, lifecycle cleanup and half-close behavior. Browser tests verify the
unsupported boundary; they are not substitutes for native tests.

## API

<docgen-index>

* [`listen(...)`](#listen)
* [`accept(...)`](#accept)
* [`closeServer(...)`](#closeserver)
* [`connect(...)`](#connect)
* [`send(...)`](#send)
* [`read(...)`](#read)
* [`disconnect(...)`](#disconnect)
* [Interfaces](#interfaces)
* [Enums](#enums)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

Native TCP byte-stream client and server APIs. Unsupported in browsers.

### listen(...)

```typescript
listen(options?: ListenOptions | undefined) => Promise<ListenResult>
```

Bind a local listener. Defaults to loopback and an OS-assigned port.

| Param         | Type                                                    |
| ------------- | ------------------------------------------------------- |
| **`options`** | <code><a href="#listenoptions">ListenOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#listenresult">ListenResult</a>&gt;</code>

--------------------


### accept(...)

```typescript
accept(options: AcceptOptions) => Promise<ConnectResult>
```

Accept one connection. Only one accept may be pending per listener.

| Param         | Type                                                    |
| ------------- | ------------------------------------------------------- |
| **`options`** | <code><a href="#acceptoptions">AcceptOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#connectresult">ConnectResult</a>&gt;</code>

--------------------


### closeServer(...)

```typescript
closeServer(options: CloseServerOptions) => Promise<CloseServerOptions>
```

Close a listener; accepted clients remain open. Idempotent for issued IDs.

| Param         | Type                                                              |
| ------------- | ----------------------------------------------------------------- |
| **`options`** | <code><a href="#closeserveroptions">CloseServerOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#closeserveroptions">CloseServerOptions</a>&gt;</code>

--------------------


### connect(...)

```typescript
connect(options: ConnectOptions) => Promise<ConnectResult>
```

Connect without blocking other plugin operations.

| Param         | Type                                                      |
| ------------- | --------------------------------------------------------- |
| **`options`** | <code><a href="#connectoptions">ConnectOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#connectresult">ConnectResult</a>&gt;</code>

--------------------


### send(...)

```typescript
send(options: SendOptions) => Promise<void>
```

Send all bytes, in invocation order. Empty data is a successful no-op.

| Param         | Type                                                |
| ------------- | --------------------------------------------------- |
| **`options`** | <code><a href="#sendoptions">SendOptions</a></code> |

--------------------


### read(...)

```typescript
read(options: ReadOptions) => Promise<ReadResult>
```

Read up to expectLen bytes. Reads queue per client; EOF and timeout reject.

| Param         | Type                                                |
| ------------- | --------------------------------------------------- |
| **`options`** | <code><a href="#readoptions">ReadOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#readresult">ReadResult</a>&gt;</code>

--------------------


### disconnect(...)

```typescript
disconnect(options: DisconnectOptions) => Promise<DisconnectResult>
```

Close the client and interrupt pending I/O. Idempotent for issued IDs.

| Param         | Type                                                            |
| ------------- | --------------------------------------------------------------- |
| **`options`** | <code><a href="#disconnectoptions">DisconnectOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#disconnectresult">DisconnectResult</a>&gt;</code>

--------------------


### Interfaces


#### ListenResult

| Prop         | Type                |
| ------------ | ------------------- |
| **`server`** | <code>number</code> |
| **`port`**   | <code>number</code> |


#### ListenOptions

| Prop            | Type                | Description                                                                      |
| --------------- | ------------------- | -------------------------------------------------------------------------------- |
| **`ipAddress`** | <code>string</code> | Local bind address; use 0.0.0.0 explicitly for LAN clients. @default "127.0.0.1" |
| **`port`**      | <code>number</code> | Local port; zero asks the OS to assign one. @default 0                           |


#### ConnectResult

| Prop         | Type                |
| ------------ | ------------------- |
| **`client`** | <code>number</code> |


#### AcceptOptions

| Prop          | Type                | Description                                         |
| ------------- | ------------------- | --------------------------------------------------- |
| **`server`**  | <code>number</code> |                                                     |
| **`timeout`** | <code>number</code> | Whole seconds; zero waits indefinitely. @default 10 |


#### CloseServerOptions

| Prop         | Type                |
| ------------ | ------------------- |
| **`server`** | <code>number</code> |


#### ConnectOptions

| Prop            | Type                | Description                                                                             |
| --------------- | ------------------- | --------------------------------------------------------------------------------------- |
| **`ipAddress`** | <code>string</code> | Server IP address or hostname.                                                          |
| **`port`**      | <code>number</code> | Server port. @default 9100                                                              |
| **`timeout`**   | <code>number</code> | Whole seconds, including connection establishment; zero waits indefinitely. @default 10 |


#### SendOptions

| Prop           | Type                                                  | Description                                                   | Default                        |
| -------------- | ----------------------------------------------------- | ------------------------------------------------------------- | ------------------------------ |
| **`client`**   | <code>number</code>                                   |                                                               |                                |
| **`data`**     | <code>string</code>                                   | UTF-8 text, canonical standard Base64, or complete Hex bytes. |                                |
| **`encoding`** | <code><a href="#dataencoding">DataEncoding</a></code> |                                                               | <code>DataEncoding.UTF8</code> |


#### ReadResult

| Prop           | Type                                                  |
| -------------- | ----------------------------------------------------- |
| **`result`**   | <code>string</code>                                   |
| **`encoding`** | <code><a href="#dataencoding">DataEncoding</a></code> |


#### ReadOptions

| Prop            | Type                                                  | Description                                                                                                               |
| --------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| **`client`**    | <code>number</code>                                   |                                                                                                                           |
| **`expectLen`** | <code>number</code>                                   | Maximum bytes to return, not a message size or minimum. @default 1024                                                     |
| **`timeout`**   | <code>number</code>                                   | Whole seconds from the start of this queued read; zero waits indefinitely. @default 10                                    |
| **`encoding`**  | <code><a href="#dataencoding">DataEncoding</a></code> | Invalid UTF-8 is returned as Base64 with encoding set accordingly. @default <a href="#dataencoding">DataEncoding.UTF8</a> |


#### DisconnectResult

| Prop         | Type                |
| ------------ | ------------------- |
| **`client`** | <code>number</code> |


#### DisconnectOptions

| Prop         | Type                |
| ------------ | ------------------- |
| **`client`** | <code>number</code> |


### Enums


#### DataEncoding

| Members      | Value                 |
| ------------ | --------------------- |
| **`UTF8`**   | <code>'utf8'</code>   |
| **`BASE64`** | <code>'base64'</code> |
| **`HEX`**    | <code>'hex'</code>    |

</docgen-api>

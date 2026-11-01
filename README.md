# capacitor-tcp-socket

A TCP Socket Plugin for Capacitor, providing TCP communication capabilities in mobile applications.

Thanks to [@ottimis](https://www.npmjs.com/package/@ottimis/tcp-socket)

## Installation

```bash
npm install capacitor-tcp-socket
npx cap sync
```

## Platform support

The plugin supports Capacitor 7 and 8. The example uses Capacitor 8 (Node 22+,
JDK 21, Android SDK 36, Xcode 26+). Browser TCP is intentionally unsupported.

On iOS, TCP uses Apple's Network.framework; there is no SwiftSocket dependency
or host Podfile Swift-version workaround. CocoaPods and Swift Package Manager
are supported. For a new Capacitor 8 app, use `npx cap add ios --packagemanager SPM`
then `npx cap sync ios`. The Swift package product is `CapacitorTcpSocket` and
requires iOS 15+. Existing CocoaPods apps can continue using `npx cap sync ios`.

For LAN connections, add `NSLocalNetworkUsageDescription` to the app's Info.plist
and allow local network access on the device. Bonjour service declarations are
only needed if your app actually browses/advertises those services. A successful
simulator connection does not establish that a physical device can reach the
same address: check the device's network, permission and server/firewall logs.

`read()` performs one read of up to `expectLen` bytes, not a persistent listener
and not a TCP message boundary. Call it again to receive subsequent data. Timeout
returns an empty result. Set `rejectOnEOF: true` to reject EOF with code `EOF`;
by default iOS preserves its legacy empty EOF result and Android rejects EOF. Concurrent reads on the
same iOS client are queued in invocation order. A zero timeout waits indefinitely. TCP servers use `listen({ ipAddress, port })`, `accept({ server, timeout })`, and
`closeServer({ server })`. Listening defaults to loopback and port 0 (OS assigned).
Use `0.0.0.0` explicitly for LAN access. Accepted client IDs use the same
`send`/`read`/`disconnect` methods. Closing a server rejects pending accept with
`CLOSED`, but leaves accepted clients open. Accept timeout rejects with `TIMEOUT`.
Only one accept may be pending per server. This does not grant background execution
on mobile platforms; the host app remains responsible for platform lifecycle rules.

See [example/README.md](example/README.md) for the real native TCP smoke test and
browser integration tests.

## Basic Usage

```typescript
import { TcpSocket } from 'capacitor-tcp-socket';

// Connect to TCP server
const connect = async () => {
  try {
    const result = await TcpSocket.connect({
      ipAddress: '192.168.1.100',
      port: 9100
    });
    console.log(`Connected with client ID: ${result.client}`);
    return result.client;
  } catch (error) {
    console.error('Connection failed:', error);
  }
};

// Send data
const sendData = async (clientId: number) => {
  try {
    await TcpSocket.send({
      client: clientId,
      data: 'Hello, TCP Server!'
    });
    console.log('Data sent successfully');
  } catch (error) {
    console.error('Send failed:', error);
  }
};

// Read data
const readData = async (clientId: number) => {
  try {
    const result = await TcpSocket.read({
      client: clientId,
      expectLen: 1024,  // Expected maximum bytes to read
      timeout: 10       // Timeout in seconds
    });
    console.log('Received data:', result.result);
    return result.result;
  } catch (error) {
    console.error('Read failed:', error);
  }
};

// Disconnect
const disconnect = async (clientId: number) => {
  try {
    const result = await TcpSocket.disconnect({
      client: clientId
    });
    console.log(`Disconnected client: ${result.client}`);
  } catch (error) {
    console.error('Disconnect failed:', error);
  }
};

// Usage example
const main = async () => {
  const clientId = await connect();
  if (clientId !== undefined) {
    await sendData(clientId);
    const data = await readData(clientId);
    await disconnect(clientId);
  }
};
```

## Working with Different Encodings

This plugin supports multiple data encodings for handling various types of data:

### Using UTF-8 Encoding (Default)

```typescript
import { TcpSocket, DataEncoding } from 'capacitor-tcp-socket';

// Send text data using UTF-8 encoding
await TcpSocket.send({
  client: clientId,
  data: 'Hello, World!',
  encoding: DataEncoding.UTF8 // Optional, UTF8 is the default
});

// Read data as UTF-8 text
const result = await TcpSocket.read({
  client: clientId,
  expectLen: 1024,
  encoding: DataEncoding.UTF8 // Optional, UTF8 is the default
});

console.log('Received text:', result.result);
console.log('Received encoding:', result.encoding);
```

### Using Base64 Encoding for Binary Data

```typescript
import { TcpSocket, DataEncoding } from 'capacitor-tcp-socket';

// Send binary data using Base64 encoding
const binaryData = new Uint8Array([0x48, 0x65, 0x6C, 0x6C, 0x6F]); // "Hello" in ASCII
const base64Data = btoa(String.fromCharCode.apply(null, binaryData));

await TcpSocket.send({
  client: clientId,
  data: base64Data,
  encoding: DataEncoding.BASE64
});

// Read binary data as Base64
const result = await TcpSocket.read({
  client: clientId,
  expectLen: 1024,
  encoding: DataEncoding.BASE64
});

// Convert Base64 back to binary if needed
const binaryResult = new Uint8Array(
  atob(result.result)
    .split('')
    .map(c => c.charCodeAt(0))
);
```

### Using Hexadecimal Encoding

```typescript
import { TcpSocket, DataEncoding } from 'capacitor-tcp-socket';

// Send data using hex encoding
const hexData = "48656C6C6F"; // "Hello" in hex

await TcpSocket.send({
  client: clientId,
  data: hexData,
  encoding: DataEncoding.HEX
});

// Read data as hex string
const result = await TcpSocket.read({
  client: clientId,
  expectLen: 1024,
  encoding: DataEncoding.HEX
});

console.log('Received hex data:', result.result);
// Example output: "48656C6C6F"

// Convert hex to binary if needed
function hexToBytes(hex) {
  const bytes = [];
  for (let c = 0; c < hex.length; c += 2) {
    bytes.push(parseInt(hex.substr(c, 2), 16));
  }
  return new Uint8Array(bytes);
}

const binaryFromHex = hexToBytes(result.result);
```

## Platform-Specific Considerations

### Web
- Not supported on the web platform.

### iOS
- iOS implementation uses Apple's Network.framework for asynchronous TCP communication.
- Supports setting a timeout for read operations (via the `timeout` parameter).

### Android
- Android implementation uses the standard Java Socket API.
- `read` supports the `timeout` option. If no data arrives in time, `read` returns an empty `result`.
- If the server closes the connection, `read` fails with error code `EOF`.

## Example Project

Check out the [example](https://github.com/gee1k/capacitor-tcp-socket/tree/master/example) directory to see a complete sample application.

Running the example app:

```bash
cd example
npm install
npm start
```

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

TCP Socket Plugin interface for Capacitor
Provides methods for TCP socket communication

### listen(...)

```typescript
listen(options: ListenOptions) => Promise<ListenResult>
```

Bind and listen for incoming TCP connections. Defaults to loopback and an OS-assigned port.

| Param         | Type                                                    |
| ------------- | ------------------------------------------------------- |
| **`options`** | <code><a href="#listenoptions">ListenOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#listenresult">ListenResult</a>&gt;</code>

--------------------


### accept(...)

```typescript
accept(options: AcceptOptions) => Promise<ConnectResult>
```

Accept the next incoming connection. The returned client supports send/read/disconnect.

| Param         | Type                                                    |
| ------------- | ------------------------------------------------------- |
| **`options`** | <code><a href="#acceptoptions">AcceptOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#connectresult">ConnectResult</a>&gt;</code>

--------------------


### closeServer(...)

```typescript
closeServer(options: CloseServerOptions) => Promise<CloseServerOptions>
```

Stop listening and reject pending accepts. Already accepted clients remain open.

| Param         | Type                                                              |
| ------------- | ----------------------------------------------------------------- |
| **`options`** | <code><a href="#closeserveroptions">CloseServerOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#closeserveroptions">CloseServerOptions</a>&gt;</code>

--------------------


### connect(...)

```typescript
connect(options: ConnectOptions) => Promise<ConnectResult>
```

Connects to a TCP server

| Param         | Type                                                      | Description                                      |
| ------------- | --------------------------------------------------------- | ------------------------------------------------ |
| **`options`** | <code><a href="#connectoptions">ConnectOptions</a></code> | Connection options including IP address and port |

**Returns:** <code>Promise&lt;<a href="#connectresult">ConnectResult</a>&gt;</code>

--------------------


### send(...)

```typescript
send(options: SendOptions) => Promise<void>
```

Sends data to a connected TCP server

| Param         | Type                                                | Description                                         |
| ------------- | --------------------------------------------------- | --------------------------------------------------- |
| **`options`** | <code><a href="#sendoptions">SendOptions</a></code> | Send options including client ID, data and encoding |

--------------------


### read(...)

```typescript
read(options: ReadOptions) => Promise<ReadResult>
```

Reads data from a connected TCP server

| Param         | Type                                                | Description                                                   |
| ------------- | --------------------------------------------------- | ------------------------------------------------------------- |
| **`options`** | <code><a href="#readoptions">ReadOptions</a></code> | Read options including client ID, expected length and timeout |

**Returns:** <code>Promise&lt;<a href="#readresult">ReadResult</a>&gt;</code>

--------------------


### disconnect(...)

```typescript
disconnect(options: DisconnectOptions) => Promise<DisconnectResult>
```

Disconnects from a TCP server

| Param         | Type                                                            | Description                       |
| ------------- | --------------------------------------------------------------- | --------------------------------- |
| **`options`** | <code><a href="#disconnectoptions">DisconnectOptions</a></code> | Disconnect options with client ID |

**Returns:** <code>Promise&lt;<a href="#disconnectresult">DisconnectResult</a>&gt;</code>

--------------------


### Interfaces


#### ListenResult

| Prop         | Type                |
| ------------ | ------------------- |
| **`server`** | <code>number</code> |
| **`port`**   | <code>number</code> |


#### ListenOptions

| Prop            | Type                | Description                                                      |
| --------------- | ------------------- | ---------------------------------------------------------------- |
| **`ipAddress`** | <code>string</code> | Local bind address. Use 0.0.0.0 explicitly to allow LAN clients. |
| **`port`**      | <code>number</code> | Local port; 0 asks the operating system to assign one.           |


#### ConnectResult

Result of a successful connection

| Prop         | Type                | Description                                          |
| ------------ | ------------------- | ---------------------------------------------------- |
| **`client`** | <code>number</code> | Client ID that can be used for subsequent operations |


#### AcceptOptions

| Prop          | Type                | Description                                               |
| ------------- | ------------------- | --------------------------------------------------------- |
| **`server`**  | <code>number</code> |                                                           |
| **`timeout`** | <code>number</code> | Seconds to wait; defaults to 10. Zero waits indefinitely. |


#### CloseServerOptions

| Prop         | Type                |
| ------------ | ------------------- |
| **`server`** | <code>number</code> |


#### ConnectOptions

Options for connecting to a TCP server

| Prop            | Type                | Description                            | Default           |
| --------------- | ------------------- | -------------------------------------- | ----------------- |
| **`ipAddress`** | <code>string</code> | IP address of the server to connect to |                   |
| **`port`**      | <code>number</code> | Port number of the TCP server          | <code>9100</code> |


#### SendOptions

Options for sending data to a TCP server

| Prop           | Type                                                  | Description                            | Default                        |
| -------------- | ----------------------------------------------------- | -------------------------------------- | ------------------------------ |
| **`client`**   | <code>number</code>                                   | Client ID from a previous connect call |                                |
| **`data`**     | <code>string</code>                                   | Data string to send to the server      |                                |
| **`encoding`** | <code><a href="#dataencoding">DataEncoding</a></code> | Encoding type for the data             | <code>DataEncoding.UTF8</code> |


#### ReadResult

Result of a read operation

| Prop           | Type                                                  | Description                                                                                                          |
| -------------- | ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| **`result`**   | <code>string</code>                                   | Data read from the server Can be UTF-8 string, Base64 encoded string, or Hex string depending on the encoding option |
| **`encoding`** | <code><a href="#dataencoding">DataEncoding</a></code> | The encoding of the returned result                                                                                  |


#### ReadOptions

Options for reading data from a TCP server

| Prop              | Type                                                  | Description                                                                                                                | Default                        |
| ----------------- | ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| **`rejectOnEOF`** | <code>boolean</code>                                  | Reject with code EOF when the peer closes the connection. Defaults to false on iOS for compatibility, and true on Android. |                                |
| **`client`**      | <code>number</code>                                   | Client ID from a previous connect call                                                                                     |                                |
| **`expectLen`**   | <code>number</code>                                   | Expected number of bytes to read                                                                                           |                                |
| **`timeout`**     | <code>number</code>                                   | Read timeout in seconds                                                                                                    | <code>10</code>                |
| **`encoding`**    | <code><a href="#dataencoding">DataEncoding</a></code> | Preferred encoding for returned data                                                                                       | <code>DataEncoding.UTF8</code> |


#### DisconnectResult

Result of a disconnect operation

| Prop         | Type                | Description                     |
| ------------ | ------------------- | ------------------------------- |
| **`client`** | <code>number</code> | Client ID that was disconnected |


#### DisconnectOptions

Options for disconnecting from a TCP server

| Prop         | Type                | Description                            |
| ------------ | ------------------- | -------------------------------------- |
| **`client`** | <code>number</code> | Client ID from a previous connect call |


### Enums


#### DataEncoding

| Members      | Value                 | Description         |
| ------------ | --------------------- | ------------------- |
| **`UTF8`**   | <code>'utf8'</code>   | UTF-8 text encoding |
| **`BASE64`** | <code>'base64'</code> | Base64 encoded data |
| **`HEX`**    | <code>'hex'</code>    | Hexadecimal string  |

</docgen-api>

# capacitor-tcp-socket

A TCP Socket Plugin for Capacitor, providing TCP communication capabilities in mobile applications.

Thanks to [@ottimis](https://www.npmjs.com/package/@ottimis/tcp-socket)

## Installation

```bash
npm install capacitor-tcp-socket
npx cap sync
```

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
      timeout: 10       // Timeout in seconds, iOS only
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
- iOS implementation uses the SwiftSocket library for TCP functionality.
- Supports setting a timeout for read operations (via the `timeout` parameter).

### Android
- Android implementation uses the standard Java Socket API.
- Currently, the read timeout parameter is not supported on Android.

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


#### ConnectResult

Result of a successful connection

| Prop         | Type                | Description                                          |
| ------------ | ------------------- | ---------------------------------------------------- |
| **`client`** | <code>number</code> | Client ID that can be used for subsequent operations |


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

| Prop            | Type                                                  | Description                            | Default                        |
| --------------- | ----------------------------------------------------- | -------------------------------------- | ------------------------------ |
| **`client`**    | <code>number</code>                                   | Client ID from a previous connect call |                                |
| **`expectLen`** | <code>number</code>                                   | Expected number of bytes to read       |                                |
| **`timeout`**   | <code>number</code>                                   | Read timeout in seconds                | <code>10</code>                |
| **`encoding`**  | <code><a href="#dataencoding">DataEncoding</a></code> | Preferred encoding for returned data   | <code>DataEncoding.UTF8</code> |


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

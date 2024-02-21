# capacitor-tcp-socket

A TCP Socket Plugin for capacitor

Thanks [@ottimis](https://www.npmjs.com/package/@ottimis/tcp-socket)

## Install

```bash
npm install capacitor-tcp-socket
npx cap sync
```

## API

<docgen-index>

* [`connect(...)`](#connect)
* [`send(...)`](#send)
* [`read(...)`](#read)
* [`disconnect(...)`](#disconnect)
* [Interfaces](#interfaces)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### connect(...)

```typescript
connect(options: ConnectOptions) => Promise<ConnectResult>
```

| Param         | Type                                                      |
| ------------- | --------------------------------------------------------- |
| **`options`** | <code><a href="#connectoptions">ConnectOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#connectresult">ConnectResult</a>&gt;</code>

--------------------


### send(...)

```typescript
send(options: SendOptions) => Promise<void>
```

| Param         | Type                                                |
| ------------- | --------------------------------------------------- |
| **`options`** | <code><a href="#sendoptions">SendOptions</a></code> |

--------------------


### read(...)

```typescript
read(options: ReadOptions) => Promise<ReadResult>
```

| Param         | Type                                                |
| ------------- | --------------------------------------------------- |
| **`options`** | <code><a href="#readoptions">ReadOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#readresult">ReadResult</a>&gt;</code>

--------------------


### disconnect(...)

```typescript
disconnect(options: DisconnectOptions) => Promise<DisconnectResult>
```

| Param         | Type                                                            |
| ------------- | --------------------------------------------------------------- |
| **`options`** | <code><a href="#disconnectoptions">DisconnectOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#disconnectresult">DisconnectResult</a>&gt;</code>

--------------------


### Interfaces


#### ConnectResult

| Prop         | Type                |
| ------------ | ------------------- |
| **`client`** | <code>number</code> |


#### ConnectOptions

| Prop            | Type                |
| --------------- | ------------------- |
| **`ipAddress`** | <code>string</code> |
| **`port`**      | <code>number</code> |


#### SendOptions

| Prop         | Type                |
| ------------ | ------------------- |
| **`client`** | <code>number</code> |
| **`data`**   | <code>string</code> |


#### ReadResult

| Prop         | Type                |
| ------------ | ------------------- |
| **`result`** | <code>string</code> |


#### ReadOptions

| Prop            | Type                |
| --------------- | ------------------- |
| **`client`**    | <code>number</code> |
| **`expectLen`** | <code>number</code> |


#### DisconnectResult

| Prop         | Type                |
| ------------ | ------------------- |
| **`client`** | <code>number</code> |


#### DisconnectOptions

| Prop         | Type                |
| ------------ | ------------------- |
| **`client`** | <code>number</code> |

</docgen-api>

/** Native TCP byte-stream client and server APIs. Unsupported in browsers. */
export interface TcpSocketPlugin {
  /** Bind a local listener. Defaults to loopback and an OS-assigned port. */
  listen(options?: ListenOptions): Promise<ListenResult>;
  /** Accept one connection. Only one accept may be pending per listener. */
  accept(options: AcceptOptions): Promise<ConnectResult>;
  /** Close a listener; accepted clients remain open. Idempotent for issued IDs. */
  closeServer(options: CloseServerOptions): Promise<CloseServerOptions>;
  /** Connect without blocking other plugin operations. */
  connect(options: ConnectOptions): Promise<ConnectResult>;
  /** Send all bytes, in invocation order. Empty data is a successful no-op. */
  send(options: SendOptions): Promise<void>;
  /** Read up to expectLen bytes. Reads queue per client; EOF and timeout reject. */
  read(options: ReadOptions): Promise<ReadResult>;
  /** Close the client and interrupt pending I/O. Idempotent for issued IDs. */
  disconnect(options: DisconnectOptions): Promise<DisconnectResult>;
}

export enum DataEncoding {
  UTF8 = 'utf8',
  BASE64 = 'base64',
  HEX = 'hex',
}

/** Stable error codes; native error message text is diagnostic only. */
export type TcpSocketErrorCode =
  | 'INVALID_ARGUMENT'
  | 'TIMEOUT'
  | 'EOF'
  | 'CLOSED'
  | 'BUSY'
  | 'CONNECT_FAILED'
  | 'LISTEN_FAILED'
  | 'IO_ERROR'
  | 'UNIMPLEMENTED';

export interface TcpSocketError extends Error {
  code: TcpSocketErrorCode;
}

export interface ConnectOptions {
  /** Server IP address or hostname. */
  ipAddress: string;
  /** Server port. @default 9100 */
  port?: number;
  /** Whole seconds, including connection establishment; zero waits indefinitely. @default 10 */
  timeout?: number;
}
export interface ConnectResult {
  client: number;
}
export interface SendOptions {
  client: number;
  /** UTF-8 text, canonical standard Base64, or complete Hex bytes. */
  data: string;
  /** @default DataEncoding.UTF8 */
  encoding?: DataEncoding;
}
export interface ReadOptions {
  client: number;
  /** Maximum bytes to return, not a message size or minimum. @default 1024 */
  expectLen?: number;
  /** Whole seconds from the start of this queued read; zero waits indefinitely. @default 10 */
  timeout?: number;
  /** Invalid UTF-8 is returned as Base64 with encoding set accordingly. @default DataEncoding.UTF8 */
  encoding?: DataEncoding;
}
export interface ReadResult {
  result: string;
  encoding: DataEncoding;
}
export interface DisconnectOptions {
  client: number;
}
export interface DisconnectResult {
  client: number;
}
export interface ListenOptions {
  /** Local bind address; use 0.0.0.0 explicitly for LAN clients. @default "127.0.0.1" */
  ipAddress?: string;
  /** Local port; zero asks the OS to assign one. @default 0 */
  port?: number;
}
export interface ListenResult {
  server: number;
  port: number;
}
export interface AcceptOptions {
  server: number;
  /** Whole seconds; zero waits indefinitely. @default 10 */
  timeout?: number;
}
export interface CloseServerOptions {
  server: number;
}

export interface TcpSocketPlugin {
  connect(options: ConnectOptions): Promise<ConnectResult>;
  send(options: SendOptions): Promise<void>;
  read(options: ReadOptions): Promise<ReadResult>;
  disconnect(options: DisconnectOptions): Promise<DisconnectResult>;
}

// types

export interface ConnectOptions {
  ipAddress: string;
  port?: number;
}
export interface ConnectResult {
  client: number;
}

export interface SendOptions {
  client: number;
  data: string;
}

export interface ReadOptions {
  client: number;
  expectLen: number;
  /**
   * timeout in seconds.
   *
   * default: 10
   *
   * only ios supports timeout.
   */
  timeout?: number;
}

export interface ReadResult {
  result?: string;
}

export interface DisconnectOptions {
  client: number;
}

export interface DisconnectResult {
  client: number;
}

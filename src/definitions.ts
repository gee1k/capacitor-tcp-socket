/**
 * TCP Socket Plugin interface for Capacitor
 * Provides methods for TCP socket communication
 */
export interface TcpSocketPlugin {
  /**
   * Connects to a TCP server
   * @param options Connection options including IP address and port
   * @returns Promise with the client identifier
   */
  connect(options: ConnectOptions): Promise<ConnectResult>;
  
  /**
   * Sends data to a connected TCP server
   * @param options Send options including client ID, data and encoding
   * @returns Promise that resolves when data is sent
   */
  send(options: SendOptions): Promise<void>;
  
  /**
   * Reads data from a connected TCP server
   * @param options Read options including client ID, expected length and timeout
   * @returns Promise with the data read from the server
   */
  read(options: ReadOptions): Promise<ReadResult>;
  
  /**
   * Disconnects from a TCP server
   * @param options Disconnect options with client ID
   * @returns Promise with the disconnected client ID
   */
  disconnect(options: DisconnectOptions): Promise<DisconnectResult>;
}

// Connection Options

/**
 * Options for connecting to a TCP server
 */
export interface ConnectOptions {
  /** 
   * IP address of the server to connect to
   */
  ipAddress: string;
  
  /**
   * Port number of the TCP server
   * @default 9100
   */
  port?: number;
}

/**
 * Result of a successful connection
 */
export interface ConnectResult {
  /**
   * Client ID that can be used for subsequent operations
   */
  client: number;
}

/**
 * Supported encoding types for data
 */
export enum DataEncoding {
  /**
   * UTF-8 text encoding
   */
  UTF8 = 'utf8',
  
  /**
   * Base64 encoded data
   */
  BASE64 = 'base64',
  
  /**
   * Hexadecimal string
   */
  HEX = 'hex'
}

/**
 * Options for sending data to a TCP server
 */
export interface SendOptions {
  /**
   * Client ID from a previous connect call
   */
  client: number;
  
  /**
   * Data string to send to the server
   */
  data: string;
  
  /**
   * Encoding type for the data
   * @default DataEncoding.UTF8
   */
  encoding?: DataEncoding;
}

/**
 * Options for reading data from a TCP server
 */
export interface ReadOptions {
  /**
   * Client ID from a previous connect call
   */
  client: number;
  
  /**
   * Expected number of bytes to read
   */
  expectLen: number;
  
  /**
   * Read timeout in seconds
   * @default 10
   * @note Only available on iOS platform
   */
  timeout?: number;
  
  /**
   * Preferred encoding for returned data
   * @default DataEncoding.UTF8
   */
  encoding?: DataEncoding;
}

/**
 * Result of a read operation
 */
export interface ReadResult {
  /**
   * Data read from the server
   * Can be UTF-8 string, Base64 encoded string, or Hex string depending on the encoding option
   */
  result?: string;
  
  /**
   * The encoding of the returned result
   */
  encoding?: DataEncoding;
}

/**
 * Options for disconnecting from a TCP server
 */
export interface DisconnectOptions {
  /**
   * Client ID from a previous connect call
   */
  client: number;
}

/**
 * Result of a disconnect operation
 */
export interface DisconnectResult {
  /**
   * Client ID that was disconnected
   */
  client: number;
}

import { WebPlugin } from '@capacitor/core';

import type {
  ConnectOptions,
  ConnectResult,
  DisconnectOptions,
  DisconnectResult,
  ReadOptions,
  ReadResult,
  SendOptions,
  TcpSocketPlugin,
} from './definitions';

/**
 * Web implementation of the TcpSocket plugin.
 * 
 * Note: Direct TCP connections are not supported in web browsers due to security restrictions.
 * Consider using WebSockets as an alternative for web applications.
 */
export class TcpSocketWeb extends WebPlugin implements TcpSocketPlugin {
  private readonly ERROR_MESSAGE = 'TCP sockets are not supported in web browsers.';
  
  /**
   * Cannot connect directly via TCP from a browser.
   */
  connect(options: ConnectOptions): Promise<ConnectResult> {
    console.log('TCP connection attempted in web context:', options);
    return Promise.reject(new Error(this.ERROR_MESSAGE));
  }

  /**
   * Cannot send data via TCP from a browser.
   */
  send(options: SendOptions): Promise<void> {
    console.log('TCP send attempted in web context:', options);
    return Promise.reject(new Error(this.ERROR_MESSAGE));
  }

  /**
   * Cannot read data via TCP from a browser.
   */
  read(options: ReadOptions): Promise<ReadResult> {
    console.log('TCP read attempted in web context:', options);
    return Promise.reject(new Error(this.ERROR_MESSAGE));
  }

  /**
   * Cannot disconnect TCP socket from a browser.
   */
  disconnect(options: DisconnectOptions): Promise<DisconnectResult> {
    console.log('TCP disconnect attempted in web context:', options);
    return Promise.reject(new Error(this.ERROR_MESSAGE));
  }
}

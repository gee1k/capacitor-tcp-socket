import { WebPlugin } from '@capacitor/core';

import type { TcpSocketPlugin } from './definitions';

/** Browsers cannot open raw TCP sockets. Never log caller addresses or payloads. */
export class TcpSocketWeb extends WebPlugin implements TcpSocketPlugin {
  private unsupported(): never {
    throw this.unimplemented('TCP sockets are not supported in web browsers.');
  }
  async connect(): Promise<never> {
    return this.unsupported();
  }
  async send(): Promise<never> {
    return this.unsupported();
  }
  async read(): Promise<never> {
    return this.unsupported();
  }
  async disconnect(): Promise<never> {
    return this.unsupported();
  }
  async listen(): Promise<never> {
    return this.unsupported();
  }
  async accept(): Promise<never> {
    return this.unsupported();
  }
  async closeServer(): Promise<never> {
    return this.unsupported();
  }
}

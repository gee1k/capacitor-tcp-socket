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

export class TcpSocketWeb extends WebPlugin implements TcpSocketPlugin {
  connect(options: ConnectOptions): Promise<ConnectResult> {
    console.log('connect', options);
    throw new Error('Method not implemented.');
  }
  send(options: SendOptions): Promise<void> {
    console.log('send', options);
    throw new Error('Method not implemented.');
  }
  read(options: ReadOptions): Promise<ReadResult> {
    console.log('read', options);
    throw new Error('Method not implemented.');
  }
  disconnect(options: DisconnectOptions): Promise<DisconnectResult> {
    console.log('disconnect', options);
    throw new Error('Method not implemented.');
  }
}

import { WebPlugin } from '@capacitor/core';

import type { TcpSocketPlugin } from './definitions';

export class TcpSocketWeb extends WebPlugin implements TcpSocketPlugin {
  async echo(options: { value: string }): Promise<{ value: string }> {
    console.log('ECHO', options);
    return options;
  }
}

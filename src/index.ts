import { registerPlugin } from '@capacitor/core';

import type { TcpSocketPlugin } from './definitions';

const TcpSocket = registerPlugin<TcpSocketPlugin>('TcpSocket', {
  web: () => import('./web').then((m) => new m.TcpSocketWeb()),
});

export * from './definitions';
export { TcpSocket };

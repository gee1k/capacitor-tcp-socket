import { registerPlugin } from '@capacitor/core';

import { withContract } from './contract';
import type { TcpSocketPlugin } from './definitions';

const native = registerPlugin<TcpSocketPlugin>('TcpSocket', {
  web: () => import('./web').then((m) => new m.TcpSocketWeb()),
});
const TcpSocket = withContract(native);
export * from './definitions';
export { TcpSocket };

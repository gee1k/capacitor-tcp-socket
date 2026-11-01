import { TcpSocket } from 'capacitor-tcp-socket';

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function rejects(action, code) {
  try {
    await action();
  } catch (error) {
    if (error.code === code) return;
    throw new Error(`Expected ${code}, received ${error.code}: ${error.message}`);
  }
  throw new Error(`Expected ${code} rejection`);
}
async function readExact(client, expected, encoding = 'utf8', expectLen = 65536) {
  let received = '';
  const target = encoding === 'base64' ? atob(expected) : expected;
  while (received.length < target.length) {
    const response = await TcpSocket.read({ client, expectLen, timeout: 5, encoding });
    if (!response.result) throw new Error('A successful read must contain data');
    if (response.encoding !== encoding) throw new Error('Unexpected encoding');
    received += encoding === 'base64' ? atob(response.result) : response.result;
  }
  if (received !== target) throw new Error('TCP byte-stream mismatch');
}

// Same contract suite runs through the actual native bridge on both platforms.
async function runTcpContractTest() {
  for (const options of [
    { ipAddress: '' },
    { ipAddress: '127.0.0.1', port: -1 },
    { ipAddress: '127.0.0.1', port: 65536 },
    { ipAddress: '127.0.0.1', port: 1.5 },
    { ipAddress: '127.0.0.1', timeout: -1 },
    { ipAddress: '127.0.0.1', timeout: Infinity },
  ])
    await rejects(() => TcpSocket.connect(options), 'INVALID_ARGUMENT');
  await rejects(() => TcpSocket.read({ client: 2147483647 }), 'INVALID_ARGUMENT');
  const { server, port } = await TcpSocket.listen({ ipAddress: '127.0.0.1' });
  let outgoing, incoming, replacement;
  try {
    await rejects(() => TcpSocket.listen({ ipAddress: '127.0.0.1', port }), 'LISTEN_FAILED');
    await rejects(() => TcpSocket.accept({ server, timeout: 1 }), 'TIMEOUT');
    const pending = TcpSocket.accept({ server, timeout: 5 });
    await rejects(() => TcpSocket.accept({ server, timeout: 1 }), 'BUSY');
    outgoing = (await TcpSocket.connect({ ipAddress: '127.0.0.1', port, timeout: 5 })).client;
    incoming = (await pending).client;
    for (const options of [
      { expectLen: 0 },
      { expectLen: -1 },
      { expectLen: 1.2 },
      { timeout: -1 },
      { timeout: 0.2 },
      { encoding: 'bogus' },
    ]) {
      await rejects(() => TcpSocket.read({ client: incoming, ...options }), 'INVALID_ARGUMENT');
    }
    for (const options of [
      { data: 'f', encoding: 'hex' },
      { data: 'xx', encoding: 'hex' },
      { data: '!!!', encoding: 'base64' },
      { data: 'Zh==', encoding: 'base64' },
      { data: 'A', encoding: 'UTF8' },
      { data: null },
    ])
      await rejects(() => TcpSocket.send({ client: outgoing, ...options }), 'INVALID_ARGUMENT');
    for (const encoding of ['utf8', 'hex', 'base64']) await TcpSocket.send({ client: outgoing, data: '', encoding });
    await rejects(() => TcpSocket.read({ client: incoming, timeout: 1 }), 'TIMEOUT');
    // The receive that timed out must not consume/drop subsequent data.
    await TcpSocket.send({ client: outgoing, data: 'ff', encoding: 'hex' });
    const invalidUTF8 = await TcpSocket.read({ client: incoming, timeout: 5 });
    if (invalidUTF8.encoding !== 'base64' || invalidUTF8.result !== '/w==') throw new Error('UTF-8 fallback mismatch');

    let settled = false;
    const forever = TcpSocket.read({ client: incoming, expectLen: 1, timeout: 0 }).then((value) => {
      settled = true;
      return value;
    });
    await delay(100);
    if (settled) throw new Error('timeout=0 must wait for data');
    await TcpSocket.send({ client: outgoing, data: 'Z' });
    if ((await forever).result !== 'Z') throw new Error('Indefinite read mismatch');

    const first = TcpSocket.read({ client: incoming, expectLen: 1, timeout: 5 });
    const second = TcpSocket.read({ client: incoming, expectLen: 1, timeout: 5 });
    await TcpSocket.send({ client: outgoing, data: 'ab' });
    if ((await first).result !== 'a' || (await second).result !== 'b') throw new Error('Read ordering mismatch');
    await Promise.all(['A', 'B', 'C'].map((data) => TcpSocket.send({ client: outgoing, data })));
    await readExact(incoming, 'ABC', 'utf8', 1);
    await Promise.all([
      TcpSocket.send({ client: outgoing, data: 'left' }),
      TcpSocket.send({ client: incoming, data: 'right' }),
    ]);
    await Promise.all([readExact(incoming, 'left'), readExact(outgoing, 'right')]);
    const large = '0123456789abcdef'.repeat(32768); // 256 KiB binary, exceeds one native read chunk.
    await TcpSocket.send({ client: outgoing, data: large, encoding: 'hex' });
    await readExact(incoming, large, 'hex', 2147483647);

    const stopped = rejects(() => TcpSocket.accept({ server, timeout: 0 }), 'CLOSED');
    await TcpSocket.closeServer({ server });
    await stopped;
    await TcpSocket.closeServer({ server });
    await rejects(() => TcpSocket.accept({ server }), 'CLOSED');
    await TcpSocket.send({ client: incoming, data: 'still open' });
    await readExact(outgoing, 'still open');
    replacement = (await TcpSocket.listen({ ipAddress: '127.0.0.1', port })).server;
    await TcpSocket.closeServer({ server: replacement });
    await rejects(() => TcpSocket.connect({ ipAddress: '127.0.0.1', port, timeout: 2 }), 'CONNECT_FAILED');

    const closed = rejects(() => TcpSocket.read({ client: incoming, timeout: 0 }), 'CLOSED');
    const queued = rejects(() => TcpSocket.read({ client: incoming, timeout: 0 }), 'CLOSED');
    await TcpSocket.disconnect({ client: incoming });
    await Promise.all([closed, queued]);
    await TcpSocket.disconnect({ client: incoming });
    await rejects(() => TcpSocket.read({ client: incoming }), 'CLOSED');
    await rejects(() => TcpSocket.send({ client: incoming, data: '' }), 'CLOSED');
    await rejects(() => TcpSocket.read({ client: outgoing, timeout: 5 }), 'EOF');
  } finally {
    await TcpSocket.closeServer({ server });
    if (replacement !== undefined) await TcpSocket.closeServer({ server: replacement });
    if (incoming !== undefined) await TcpSocket.disconnect({ client: incoming });
    if (outgoing !== undefined) await TcpSocket.disconnect({ client: outgoing });
  }
}

export async function runTcpSmokeTest(ipAddress, port) {
  // The browser should report the native API as unsupported before native-only assertions.
  const probe = await TcpSocket.listen();
  await TcpSocket.closeServer(probe);
  await runTcpContractTest();
  const { client } = await TcpSocket.connect({ ipAddress, port });
  const passed = [
    'Unified V8 contract: validation, errors, FIFO I/O, cancellation, 256 KiB transfer, server lifecycle',
  ];
  try {
    for (const [encoding, data] of [
      ['utf8', 'first echo'],
      ['utf8', 'second echo'],
      ['hex', '00017fff'],
      ['base64', 'AAEC/w=='],
    ]) {
      await TcpSocket.send({ client, data, encoding });
      await readExact(client, data, encoding);
      passed.push(`${encoding}: ${data}`);
    }
    await TcpSocket.send({ client, data: 'buffered-read-regression' });
    await readExact(client, 'buffered-read-regression', 'utf8', 4);
    await rejects(() => TcpSocket.read({ client, timeout: 1 }), 'TIMEOUT');
    await TcpSocket.send({ client, data: 'DELAY\n' });
    await readExact(client, 'DELAY\n');
    await TcpSocket.send({ client, data: 'CLOSE\n' });
    await rejects(() => TcpSocket.read({ client, timeout: 5 }), 'EOF');
    await TcpSocket.send({ client, data: 'AFTER_EOF\n' });
    passed.push('Short reads, timeout recovery, EOF and half-close send');
    return passed;
  } finally {
    await TcpSocket.disconnect({ client });
    await TcpSocket.disconnect({ client });
  }
}

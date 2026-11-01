import { Capacitor } from '@capacitor/core';
import { TcpSocket } from 'capacitor-tcp-socket';

// Uses the installed plugin and real TCP server. No browser socket replacement.
export async function runTcpSmokeTest(ipAddress, port) {
  await runTcpServerSmokeTest();
  const { client } = await TcpSocket.connect({ ipAddress, port });
  const passed = ['TCP server listen, accept, bidirectional I/O and close'];
  const readExact = async (expected, encoding, expectLen = 1024) => {
    if (encoding === 'base64') expected = atob(expected);
    let received = '';
    while (received.length < expected.length) {
      const response = await TcpSocket.read({ client, expectLen, timeout: 5, encoding });
      if (!response.result) throw new Error('Timed out waiting for echo');
      received += encoding === 'base64' ? atob(response.result) : response.result;
    }
    if (received !== expected) throw new Error(`Echo mismatch: ${received} != ${expected}`);
  };
  try {
    for (const [encoding, data] of [
      ['utf8', 'first echo'],
      ['utf8', 'second echo'],
      ['hex', '00017fff'],
      ['base64', 'AAEC/w=='],
    ]) {
      await TcpSocket.send({ client, data, encoding });
      await readExact(data, encoding);
      passed.push(`${encoding}: ${data}`);
    }
    const burst = 'buffered-read-regression';
    await TcpSocket.send({ client, data: burst });
    await readExact(burst, 'utf8', 4);
    passed.push('Repeated short reads preserve remaining bytes');
    const empty = await TcpSocket.read({ client, expectLen: 1024, timeout: 1 });
    if (empty.result !== '') throw new Error('Expected an empty response on timeout');
    await TcpSocket.send({ client, data: 'DELAY\n' });
    await readExact('DELAY\n', 'utf8');
    passed.push('Timeout followed by delayed data');
    await TcpSocket.send({ client, data: 'CLOSE\n' });
    if (Capacitor.getPlatform() === 'ios') {
      const eof = await TcpSocket.read({ client, expectLen: 1024, timeout: 5 });
      if (eof.result !== '') throw new Error('Legacy iOS EOF must return an empty result');
      passed.push('Legacy iOS EOF remains compatible');
    }
    try {
      await TcpSocket.read({ client, expectLen: 1024, timeout: 5, rejectOnEOF: true });
      throw new Error('Expected EOF rejection');
    } catch (error) {
      if (error.code !== 'EOF') throw error;
    }
    passed.push('Peer close reports EOF');
    return passed;
  } finally {
    await TcpSocket.disconnect({ client });
    if (Capacitor.getPlatform() === 'ios') await TcpSocket.disconnect({ client });
  }
}

async function runTcpServerSmokeTest() {
  const { server, port } = await TcpSocket.listen({ ipAddress: '127.0.0.1', port: 0 });
  let outgoing;
  let incoming;
  let closed = false;
  const readText = async (client, expected) => {
    let value = '';
    while (value.length < expected.length) {
      const response = await TcpSocket.read({ client, expectLen: 2, timeout: 5, encoding: 'hex' });
      if (!response.result) throw new Error('Server round trip timed out');
      value += response.result;
    }
    if (value !== expected) throw new Error('Server round trip mismatch');
  };
  try {
    try {
      await TcpSocket.accept({ server, timeout: 1 });
      throw new Error('Accept should time out');
    } catch (error) { if (error.code !== 'TIMEOUT') throw error; }
    const pending = TcpSocket.accept({ server, timeout: 5 });
    outgoing = (await TcpSocket.connect({ ipAddress: '127.0.0.1', port })).client;
    incoming = (await pending).client;
    await TcpSocket.send({ client: outgoing, data: '00017fff', encoding: 'hex' });
    await readText(incoming, '00017fff');
    await TcpSocket.send({ client: incoming, data: 'e4b8ade69687', encoding: 'hex' });
    await readText(outgoing, 'e4b8ade69687');
    // Closing the listener rejects accept but does not close established clients.
    const stopped = TcpSocket.accept({ server, timeout: 0 }).then(
      () => { throw new Error('Closed listener accepted a connection'); },
      error => { if (error.code !== 'CLOSED') throw error; },
    );
    await TcpSocket.closeServer({ server });
    closed = true;
    await stopped;
    await TcpSocket.send({ client: incoming, data: '41', encoding: 'hex' });
    await readText(outgoing, '41');
  } finally {
    if (!closed) await TcpSocket.closeServer({ server });
    if (incoming !== undefined) await TcpSocket.disconnect({ client: incoming });
    if (outgoing !== undefined) await TcpSocket.disconnect({ client: outgoing });
  }
}

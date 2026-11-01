import { TcpSocket } from 'capacitor-tcp-socket';

// Uses the installed plugin and real TCP server. No browser socket replacement.
export async function runTcpSmokeTest(ipAddress, port) {
  const { client } = await TcpSocket.connect({ ipAddress, port });
  const passed = [];
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
    try {
      await TcpSocket.read({ client, expectLen: 1024, timeout: 5 });
      throw new Error('Expected EOF rejection');
    } catch (error) {
      if (error.code !== 'EOF') throw error;
    }
    passed.push('Peer close reports EOF');
    return passed;
  } finally {
    await TcpSocket.disconnect({ client });
  }
}

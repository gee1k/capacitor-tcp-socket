import net from 'node:net';

const port = Number(process.env.TCP_TEST_PORT || 9100);
const server = net.createServer((socket) => {
  let pending = Buffer.alloc(0);
  socket.on('error', (error) => console.error('Client:', error.message));
  socket.on('data', (chunk) => {
    pending = Buffer.concat([pending, chunk]);
    const text = pending.toString('utf8');
    if (('DELAY\n'.startsWith(text) || 'CLOSE\n'.startsWith(text)) && !text.endsWith('\n')) return;
    const data = pending;
    pending = Buffer.alloc(0);
    if (data.equals(Buffer.from('CLOSE\n'))) socket.end();
    else if (data.equals(Buffer.from('DELAY\n')))
      setTimeout(() => {
        if (!socket.destroyed) socket.write(data);
      }, 3000);
    else socket.write(data);
  });
});
server.listen(port, '0.0.0.0', () => console.log(`TCP echo server listening on ${port}`));

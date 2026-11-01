const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const ts = require('typescript');

// Execute the actual TypeScript boundary with a recording native adapter.
function source(name) {
  const code = ts.transpileModule(fs.readFileSync(`src/${name}.ts`, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2017 },
  }).outputText;
  const exports = {};
  new Function('exports', 'require', code)(exports, (path) =>
    path.startsWith('.') ? source(path.slice(2)) : require(path),
  );
  return exports;
}
const { withContract } = source('contract');
function fixture() {
  const calls = [];
  const native = Object.fromEntries(
    ['connect', 'listen', 'accept', 'closeServer', 'disconnect', 'read', 'send'].map((method) => [
      method,
      async (options) => {
        calls.push({ method, options });
        return {};
      },
    ]),
  );
  return { plugin: withContract(native), calls };
}

test('defaults and normalized complete Hex bytes cross the native boundary', async () => {
  const { plugin, calls } = fixture();
  await plugin.connect({ ipAddress: 'localhost' });
  await plugin.listen();
  await plugin.read({ client: 0 });
  await plugin.send({ client: 0, data: '0x 00 7F ff', encoding: 'hex' });
  assert.deepEqual(calls, [
    { method: 'connect', options: { ipAddress: 'localhost', port: 9100, timeout: 10 } },
    { method: 'listen', options: { ipAddress: '127.0.0.1', port: 0 } },
    { method: 'read', options: { client: 0, expectLen: 1024, timeout: 10, encoding: 'utf8' } },
    { method: 'send', options: { client: 0, data: '007Fff', encoding: 'hex' } },
  ]);
});

test('invalid runtime input rejects before calling native code', async () => {
  const { plugin, calls } = fixture();
  const bad = [
    () => plugin.connect(null),
    () => plugin.listen([]),
    () => plugin.read(undefined),
    ...[null, '', ' ', 'host name', 'host\0name', 3].map((ipAddress) => () => plugin.connect({ ipAddress })),
    ...[-1, 0, 65536, NaN, Infinity, 1.2, '9100', null, true].map(
      (port) => () => plugin.connect({ ipAddress: 'localhost', port }),
    ),
    ...[-1, NaN, Infinity, 1.2, 2147484, null].map((timeout) => () => plugin.read({ client: 0, timeout })),
    ...[0, -1, 1.5, NaN, 2147483648].map((expectLen) => () => plugin.read({ client: 0, expectLen })),
    ...[-1, NaN, 0.1, '0', null].map((client) => () => plugin.disconnect({ client })),
    ...['f', '0x0', 'gg', '+1', '0x00x1'].map((data) => () => plugin.send({ client: 0, data, encoding: 'hex' })),
    ...['Zg', 'Zh==', 'Zm9=', '***=', 'Zg==\n', '____', '='].map(
      (data) => () => plugin.send({ client: 0, data, encoding: 'base64' }),
    ),
    () => plugin.send({ client: 0, data: 'test', encoding: 'UTF8' }),
  ];
  for (const action of bad) await assert.rejects(action, { code: 'INVALID_ARGUMENT' });
  assert.equal(calls.length, 0);
});

test('valid empty sends, timeout zero, IPv6 and canonical Base64 remain accepted', async () => {
  const { plugin, calls } = fixture();
  await plugin.connect({ ipAddress: '::1', timeout: 0 });
  await plugin.read({ client: 0, timeout: 0, expectLen: 2147483647 });
  for (const encoding of ['utf8', 'hex', 'base64']) await plugin.send({ client: 0, data: '', encoding });
  for (const data of ['Zg==', 'Zm8=', 'Zm9v', 'AAEC/w==']) await plugin.send({ client: 0, data, encoding: 'base64' });
  assert.equal(calls.length, 9);
});

test('native errors retain their stable code and identity', async () => {
  const error = Object.assign(new Error('OS diagnostic'), { code: 'CONNECT_FAILED' });
  const plugin = withContract({
    connect: async () => {
      throw error;
    },
  });
  await assert.rejects(
    () => plugin.connect({ ipAddress: 'localhost' }),
    (value) => value === error,
  );
});

test('all browser methods reject UNIMPLEMENTED without logging caller data', async () => {
  const { TcpSocketWeb } = source('web');
  const web = new TcpSocketWeb();
  const logs = [];
  const original = console.log;
  console.log = (...args) => logs.push(args);
  try {
    for (const method of ['connect', 'send', 'read', 'disconnect', 'listen', 'accept', 'closeServer']) {
      await assert.rejects(() => web[method]({ data: 'private-test-payload' }), { code: 'UNIMPLEMENTED' });
    }
    assert.equal(logs.length, 0);
  } finally {
    console.log = original;
  }
});

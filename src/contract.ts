import { DataEncoding } from './definitions';
import type { TcpSocketPlugin, TcpSocketError } from './definitions';

function invalid(message: string): never {
  const error = new Error(message) as TcpSocketError;
  error.code = 'INVALID_ARGUMENT';
  throw error;
}
function options(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) invalid('Options must be an object');
  return value as Record<string, unknown>;
}
function integer(value: unknown, name: string, minimum: number, maximum: number, fallback?: number): number {
  if (value === undefined && fallback !== undefined) return fallback;
  if (typeof value !== 'number' || !Number.isInteger(value) || value < minimum || value > maximum) {
    invalid(`${name} must be an integer between ${minimum} and ${maximum}`);
  }
  return value as number;
}
function host(value: unknown, fallback?: string): string {
  if (value === undefined && fallback !== undefined) return fallback;
  if (typeof value !== 'string' || !value.trim() || /[\s\0]/.test(value)) invalid('Invalid IP address or hostname');
  return value as string;
}
function encoding(value: unknown): DataEncoding {
  if (value === undefined) return DataEncoding.UTF8;
  if (!Object.values(DataEncoding).includes(value as DataEncoding)) invalid('Unsupported encoding');
  return value as DataEncoding;
}
const id = (value: unknown, name: string) => integer(value, name, 0, 2147483647);
const timeout = (value: unknown) => integer(value, 'timeout', 0, 2147483, 10);

/** Validate before crossing either native bridge. Never log payloads. */
export function withContract(native: TcpSocketPlugin): TcpSocketPlugin {
  return {
    async connect(input) {
      const o = options(input);
      return native.connect({
        ipAddress: host(o.ipAddress),
        port: integer(o.port, 'port', 1, 65535, 9100),
        timeout: timeout(o.timeout),
      });
    },
    async listen(input = {}) {
      const o = options(input);
      return native.listen({ ipAddress: host(o.ipAddress, '127.0.0.1'), port: integer(o.port, 'port', 0, 65535, 0) });
    },
    async accept(input) {
      const o = options(input);
      return native.accept({ server: id(o.server, 'server'), timeout: timeout(o.timeout) });
    },
    async closeServer(input) {
      const o = options(input);
      return native.closeServer({ server: id(o.server, 'server') });
    },
    async disconnect(input) {
      const o = options(input);
      return native.disconnect({ client: id(o.client, 'client') });
    },
    async read(input) {
      const o = options(input);
      return native.read({
        client: id(o.client, 'client'),
        expectLen: integer(o.expectLen, 'expectLen', 1, 2147483647, 1024),
        timeout: timeout(o.timeout),
        encoding: encoding(o.encoding),
      });
    },
    async send(input) {
      const o = options(input);
      const client = id(o.client, 'client');
      const format = encoding(o.encoding);
      if (typeof o.data !== 'string') invalid('data must be a string');
      let data = o.data as string;
      if (format === DataEncoding.HEX) {
        data = data.replace(/\s/g, '').replace(/^0x/i, '');
        if (!/^(?:[0-9a-fA-F]{2})*$/.test(data)) invalid('Hex must contain complete bytes');
      } else if (format === DataEncoding.BASE64) {
        if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(data)) invalid('Invalid Base64');
        const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        if (
          (data.endsWith('==') && (alphabet.indexOf(data[data.length - 3]) & 15) !== 0) ||
          (data.endsWith('=') && !data.endsWith('==') && (alphabet.indexOf(data[data.length - 2]) & 3) !== 0)
        )
          invalid('Noncanonical Base64');
      }
      return native.send({ client, data, encoding: format });
    },
  };
}

import { mkdtemp, copyFile, symlink, mkdir, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const example = fileURLToPath(new URL('..', import.meta.url));
const fixture = await mkdtemp(join(tmpdir(), 'tcp-spm-example-'));
for (const file of ['package.json', 'capacitor.config.json']) {
  await copyFile(join(example, file), join(fixture, file));
}
await symlink(join(example, 'dist'), join(fixture, 'dist'), 'dir');
await mkdir(join(fixture, 'node_modules'));
for (const entry of await readdir(join(example, 'node_modules'))) {
  if (entry !== 'capacitor-tcp-socket') {
    await symlink(join(example, 'node_modules', entry), join(fixture, 'node_modules', entry));
  }
}
// Test the published file layout, not just the full repository checkout.
const packed = JSON.parse(
  execFileSync('npm', ['pack', '--json', '--pack-destination', fixture], {
    cwd: resolve(example, '..'),
    encoding: 'utf8',
  }),
)[0];
const plugin = join(fixture, 'node_modules', 'capacitor-tcp-socket');
await mkdir(plugin);
execFileSync('tar', ['-xzf', join(fixture, packed.filename), '--strip-components=1', '-C', plugin]);
const cap = resolve(example, 'node_modules/.bin/cap');
execFileSync(cap, ['add', 'ios', '--packagemanager', 'SPM'], { cwd: fixture, stdio: 'inherit' });
execFileSync(cap, ['sync', 'ios'], { cwd: fixture, stdio: 'inherit' });
if (process.platform === 'darwin') {
  execFileSync(
    'xcodebuild',
    [
      '-project',
      'ios/App/App.xcodeproj',
      '-scheme',
      'App',
      '-sdk',
      'iphonesimulator',
      '-configuration',
      'Debug',
      'CODE_SIGNING_ALLOWED=NO',
      'build',
    ],
    { cwd: fixture, stdio: 'inherit' },
  );
} else {
  console.log('SPM example generated and synced. Compilation requires macOS/Xcode.');
}
console.log(`SPM example: ${fixture}`);

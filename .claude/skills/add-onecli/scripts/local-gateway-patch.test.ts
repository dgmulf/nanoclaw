import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, expect, it, vi } from 'vitest';
import { parse } from 'yaml';
import {
  ensureLocalGatewayPatch,
  managesGateway,
  PATCHED_GATEWAY_IMAGE,
  withPatchedGatewayImage,
} from './local-gateway-patch.js';

const dirs: string[] = [];
afterEach(() => {
  dirs.splice(0).forEach((dir) => fs.rmSync(dir, { recursive: true, force: true }));
});
const compose = `name: onecli
services:
  postgres:
    image: postgres:18-alpine
    volumes: [pgdata:/var/lib/postgresql]
  onecli:
    image: ghcr.io/onecli/onecli:\${ONECLI_VERSION:-latest}
    environment:
      NEXTAUTH_SECRET: \${NEXTAUTH_SECRET:-}
    volumes: [app-data:/app/data]
volumes:
  pgdata:
  app-data:
`;
function fixture(image = 'ghcr.io/onecli/onecli:1.42.0') {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'onecli-patch-'));
  dirs.push(dir);
  const composeFile = path.join(dir, 'docker-compose.yml');
  fs.writeFileSync(composeFile, compose);
  const info = {
    Config: {
      Image: image,
      Labels: {
        'com.docker.compose.service': 'onecli',
        'com.docker.compose.project.working_dir': dir,
      } as Record<string, string>,
    },
    NetworkSettings: { Ports: { '10254/tcp': [{ HostIp: '172.17.0.1', HostPort: '10254' }] } },
  };
  const run = vi.fn((args: string[]) => (args[0] === 'inspect' ? JSON.stringify([info]) : ''));
  return { composeFile, info, run, checkHealth: vi.fn(async () => true) };
}
const url = 'http://172.17.0.1:10254';

it('changes only the service image, preserving interpolation, credentials references and volumes', () => {
  const expected = parse(compose);
  expected.services.onecli.image = PATCHED_GATEWAY_IMAGE;
  const result = withPatchedGatewayImage(compose);
  expect(parse(result)).toEqual(expected);
  expect(withPatchedGatewayImage(result)).toBe(result);
  expect(() => withPatchedGatewayImage('services: {}')).toThrow();
});
it('builds and applies backports to a fresh stock installation without restarting postgres', async () => {
  const f = fixture();
  expect(await ensureLocalGatewayPatch(url, f)).toBe('applied');
  expect(f.run.mock.calls.map(([args]) => args[0])).toEqual(['inspect', 'build', 'compose']);
  expect(f.run.mock.calls[2][0]).toEqual([
    'compose',
    '-f',
    f.composeFile,
    'up',
    '-d',
    '--no-deps',
    '--pull',
    'never',
    'onecli',
  ]);
  expect(parse(fs.readFileSync(f.composeFile, 'utf8')).services.onecli.image).toBe(PATCHED_GATEWAY_IMAGE);
  const backup = fs.readdirSync(path.dirname(f.composeFile)).find((name) => name.endsWith('.bak'))!;
  expect(fs.readFileSync(path.join(path.dirname(f.composeFile), backup), 'utf8')).toBe(compose);
  expect(fs.statSync(path.join(path.dirname(f.composeFile), backup)).mode & 0o777).toBe(0o600);
});
it('upgrades the existing routing-only image and skips a fully patched installation', async () => {
  const f = fixture('onecli-nanoclaw-codex:1.42.0');
  await ensureLocalGatewayPatch(url, f);
  f.info.Config.Image = PATCHED_GATEWAY_IMAGE;
  f.info.Config.Labels['io.nanoclaw.onecli-patches'] = 'codex-account-routing,openai-refresh-client-id';
  f.run.mockClear();
  expect(await ensureLocalGatewayPatch(url, f)).toBe('current');
  expect(f.run).toHaveBeenCalledTimes(1);
});
it('leaves remote and unrelated gateways untouched', async () => {
  const f = fixture();
  expect(await ensureLocalGatewayPatch('https://gateway.example.test', f)).toBe('external');
  expect(f.run).toHaveBeenCalledTimes(1);
  expect(managesGateway(f.info, 'http://172.17.0.1:9999', f.composeFile)).toBe(false);
  f.info.Config.Labels['com.docker.compose.project.working_dir'] = '/another/install';
  expect(await ensureLocalGatewayPatch(url, f)).toBe('external');
  expect(fs.readFileSync(f.composeFile, 'utf8')).toBe(compose);
});
it('rejects an unsupported gateway version before building or changing deployment files', async () => {
  const f = fixture('ghcr.io/onecli/onecli:1.43.1');
  await expect(ensureLocalGatewayPatch(url, f)).rejects.toThrow('refusing to replace');
  expect(f.run).toHaveBeenCalledTimes(1);
  expect(fs.readFileSync(f.composeFile, 'utf8')).toBe(compose);
});
it('leaves the existing deployment intact if compilation fails', async () => {
  const f = fixture();
  f.run.mockImplementation((args) => {
    if (args[0] === 'build') throw new Error('Build failed');
    return JSON.stringify([f.info]);
  });
  await expect(ensureLocalGatewayPatch(url, f)).rejects.toThrow('Build failed');
  expect(fs.readFileSync(f.composeFile, 'utf8')).toBe(compose);
  expect(f.run.mock.calls.some(([args]) => args[0] === 'compose')).toBe(false);
});
it('restores the previous image and Compose configuration when health verification fails', async () => {
  const f = fixture();
  f.checkHealth.mockResolvedValue(false);
  await expect(ensureLocalGatewayPatch(url, f)).rejects.toThrow('failed its health');
  expect(fs.readFileSync(f.composeFile, 'utf8')).toBe(compose);
  expect(f.run.mock.calls.filter(([args]) => args[0] === 'compose')).toHaveLength(2);
});

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

vi.mock('child_process', () => ({
  execFileSync: vi.fn((_command: string, args: string[]) => {
    if (args[0] === 'version') return '2.2.5';
    if (args[0] === 'config') return JSON.stringify({ data: 'http://172.17.0.1:10254' });
    throw new Error('Unexpected external command');
  }),
  execSync: vi.fn(() => {
    throw new Error('Reuse must not run the upstream installer');
  }),
}));
vi.mock('./local-gateway-patch.js', () => ({ ensureLocalGatewayPatch: vi.fn(async () => 'applied') }));
vi.mock('../../../../setup/status.js', () => ({ emitStatus: vi.fn() }));
import { ensureLocalGatewayPatch } from './local-gateway-patch.js';
import { emitStatus } from '../../../../setup/status.js';
import { run } from './setup.js';

let dir: string;
beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'onecli-setup-backports-'));
  vi.spyOn(os, 'homedir').mockReturnValue(dir);
  vi.spyOn(process, 'cwd').mockReturnValue(dir);
  vi.stubEnv('NANOCLAW_ONECLI_API_HOST', '');
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response('{}', { status: 200 })),
  );
  vi.mocked(ensureLocalGatewayPatch).mockResolvedValue('applied');
});
afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  vi.clearAllMocks();
  fs.rmSync(dir, { recursive: true, force: true });
});
it('automatically applies fork backports even when normal setup detects an existing gateway', async () => {
  await run([]);
  expect(ensureLocalGatewayPatch).toHaveBeenCalledWith('http://172.17.0.1:10254');
  expect(emitStatus).toHaveBeenCalledWith('ONECLI', expect.objectContaining({ STATUS: 'success', REUSED: true }));
});
it('does not report setup success if the fork backports fail', async () => {
  vi.mocked(ensureLocalGatewayPatch).mockRejectedValue(new Error('Gateway build failed'));
  await expect(run(['--reuse'])).rejects.toThrow('Gateway build failed');
  expect(emitStatus).not.toHaveBeenCalled();
});

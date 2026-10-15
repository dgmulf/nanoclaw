/** Fork-owned backports for the supported local gateway; never opens the vault. */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseDocument } from 'yaml';

export const PATCHED_GATEWAY_IMAGE = 'onecli-nanoclaw-codex:1.42.0-refresh1';
const PATCH_LABEL = 'codex-account-routing,openai-refresh-client-id';
const CONTEXT = fileURLToPath(new URL('../../../../container/onecli-codex-routing/', import.meta.url));
const STOCK_DIGEST = 'ghcr.io/onecli/onecli@sha256:8d4a3300e915259a2fcff13614ecd7394bfd35c75d6a64d69f28a28dd23f30fe';
const SUPPORTED_IMAGES = new Set([
  'ghcr.io/onecli/onecli:1.42.0',
  STOCK_DIGEST,
  'onecli-nanoclaw-codex:1.42.0',
  PATCHED_GATEWAY_IMAGE,
]);

type Run = (args: string[], inherit?: boolean) => string;
const docker: Run = (args, inherit = false) =>
  execFileSync('docker', args, {
    encoding: 'utf8',
    stdio: inherit ? 'inherit' : ['ignore', 'pipe', 'pipe'],
  }) ?? '';

export function withPatchedGatewayImage(compose: string): string {
  const doc = parseDocument(compose);
  if (doc.errors.length) throw new Error('Cannot parse the local OneCLI Compose file');
  if (!doc.hasIn(['services', 'onecli', 'image']) || doc.hasIn(['services', 'onecli', 'build'])) {
    throw new Error('Expected an image-based OneCLI service');
  }
  doc.setIn(['services', 'onecli', 'image'], PATCHED_GATEWAY_IMAGE);
  return doc.toString();
}

interface GatewayInspection {
  Config: { Image: string; Labels?: Record<string, string> };
  NetworkSettings: { Ports: Record<string, Array<{ HostIp: string; HostPort: string }> | null> };
}

export function managesGateway(info: GatewayInspection, url: string, composeFile: string): boolean {
  const target = new URL(url);
  if (target.protocol !== 'http:' || (target.pathname !== '/' && target.pathname !== '')) return false;
  const labels = info.Config.Labels ?? {};
  if (
    labels['com.docker.compose.service'] !== 'onecli' ||
    labels['com.docker.compose.project.working_dir'] !== path.dirname(composeFile)
  )
    return false;
  return (info.NetworkSettings.Ports['10254/tcp'] ?? []).some(
    ({ HostIp, HostPort }) =>
      HostPort === (target.port || '80') &&
      (target.hostname === HostIp ||
        (['127.0.0.1', '0.0.0.0', '::'].includes(HostIp) &&
          ['localhost', '127.0.0.1', '[::1]'].includes(target.hostname))),
  );
}

async function healthy(url: string): Promise<boolean> {
  for (let attempt = 0; attempt < 90; attempt++) {
    try {
      const response = await fetch(`${url.replace(/\/$/, '')}/v1/health`, { signal: AbortSignal.timeout(2000) });
      // The image healthcheck probes both Node's API and the Rust proxy.
      if (response.ok && docker(['inspect', '--format', '{{.State.Health.Status}}', 'onecli']).trim() === 'healthy')
        return true;
    } catch {
      /* Wait for the existing entrypoint to start. */
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  return false;
}

export async function ensureLocalGatewayPatch(
  url: string,
  options: {
    composeFile?: string;
    run?: Run;
    checkHealth?: (url: string) => Promise<boolean>;
  } = {},
): Promise<'applied' | 'current' | 'external'> {
  const composeFile = options.composeFile ?? path.join(os.homedir(), '.onecli', 'docker-compose.yml');
  if (!fs.existsSync(composeFile)) return 'external';
  const run = options.run ?? docker;
  // Fail on Docker errors rather than silently reporting an unpatched local gateway ready.
  const inspections = JSON.parse(run(['inspect', 'onecli'])) as GatewayInspection[];
  if (!inspections[0] || !managesGateway(inspections[0], url, composeFile)) return 'external';
  const info = inspections[0];
  if (!SUPPORTED_IMAGES.has(info.Config.Image)) {
    throw new Error(`Local OneCLI image ${info.Config.Image} is not the supported 1.42.0 base; refusing to replace it`);
  }
  const before = fs.readFileSync(composeFile, 'utf8');
  const after = withPatchedGatewayImage(before);
  if (
    info.Config.Image === PATCHED_GATEWAY_IMAGE &&
    info.Config.Labels?.['io.nanoclaw.onecli-patches'] === PATCH_LABEL &&
    parseDocument(before).getIn(['services', 'onecli', 'image']) === PATCHED_GATEWAY_IMAGE
  )
    return 'current';

  console.log(
    'Building OneCLI 1.42.0 with Codex routing and OAuth refresh backports (first build can take several minutes)…',
  );
  // A failed build leaves both the running gateway and Compose file untouched.
  run(['build', '--progress=plain', '-t', PATCHED_GATEWAY_IMAGE, CONTEXT], true);
  const backup = `${composeFile}.nanoclaw-${new Date().toISOString().replace(/:/g, '-')}.bak`;
  fs.writeFileSync(backup, before, { mode: 0o600, flag: 'wx' });
  const up = ['compose', '-f', composeFile, 'up', '-d', '--no-deps', '--pull', 'never', 'onecli'];
  fs.writeFileSync(composeFile, after);
  try {
    run(up, true);
    if (!(await (options.checkHealth ?? healthy)(url))) throw new Error('Patched OneCLI failed its health check');
    return 'applied';
  } catch (error) {
    fs.writeFileSync(composeFile, before);
    try {
      run(up, true);
    } catch {
      throw new Error(`OneCLI patch failed and rollback failed; restore ${backup}`);
    }
    throw error;
  }
}

if (process.argv[1] && import.meta.url === `file://${process.argv[1]}`) {
  const { readEnvFile } = await import('../../../../src/env.js');
  const url = process.env.ONECLI_URL || readEnvFile(['ONECLI_URL']).ONECLI_URL;
  if (!url) throw new Error('ONECLI_URL is required');
  const result = await ensureLocalGatewayPatch(url);
  if (result === 'external') throw new Error('Gateway is not managed locally; apply this fork on the gateway host');
  console.log(`OneCLI backports: ${result}`);
}

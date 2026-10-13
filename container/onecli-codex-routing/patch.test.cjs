const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { patch } = require('./patch.cjs');
const source = fs.readFileSync(process.env.ONECLI_TEST_BUNDLE, 'utf8');

function generator(bundle) {
  const start = bundle.indexOf('p4=');
  const end = bundle.indexOf(',p3=', start);
  return vm.runInNewContext('(' + bundle.slice(start + 3, end) + ')', { Buffer });
}

test('real account routes locally while credentials stay placeholders', () => {
  const stub = JSON.parse(generator(patch(source))('test-account-id'));
  assert.equal(stub.tokens.account_id, 'test-account-id');
  assert.equal(stub.tokens.access_token, 'onecli-managed');
  assert.equal(stub.tokens.refresh_token, 'onecli-managed');
  const claims = JSON.parse(Buffer.from(stub.tokens.id_token.split('.')[1], 'base64url'));
  assert.equal(claims['https://api.openai.com/auth'].chatgpt_account_id, 'test-account-id');
  assert.equal(claims['https://api.openai.com/auth'].chatgpt_plan_type, undefined);
});

test('unknown account keeps the original placeholder contract', () => {
  const original = JSON.parse(generator(source)());
  const patched = JSON.parse(generator(patch(source))());
  delete original.last_refresh;
  delete patched.last_refresh;
  assert.deepEqual(patched, original);
});

test('unexpected or already-patched bundles fail closed', () => {
  assert.throws(() => patch('unexpected bundle'));
  assert.throws(() => patch(patch(source)));
});

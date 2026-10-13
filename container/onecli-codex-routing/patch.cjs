const fs = require('node:fs');

// Backport the account-id portion of onecli/onecli#578 to the pinned 1.42.0
// bundle. No vault values are read here; only its existing metadata is used.
function patch(source) {
  const definition = /p4=\(\)=>JSON\.stringify\((\{auth_mode:"chatgpt".*?),null,2\),p3=/;
  if (!definition.test(source)) throw new Error('Unexpected Codex stub generator');
  source = source.replace(definition, (_, object) =>
    `p4=(accountId)=>{const stub=${object};` +
    `if(typeof accountId==="string"&&accountId&&accountId!=="onecli-managed"){` +
    `stub.tokens.account_id=accountId;` +
    `const parts=stub.tokens.id_token.split(".");` +
    `const claims=JSON.parse(Buffer.from(parts[1],"base64url").toString());` +
    `claims["https://api.openai.com/auth"].chatgpt_account_id=accountId;` +
    `delete claims["https://api.openai.com/auth"].chatgpt_plan_type;` +
    `parts[1]=Buffer.from(JSON.stringify(claims)).toString("base64url");` +
    `stub.tokens.id_token=parts.join(".");}` +
    `return JSON.stringify(stub,null,2)},p3=`);
  const perAgent = 'containerPath:`${p5}/auth.json`,content:p4()';
  if (source.split(perAgent).length !== 2) throw new Error('Unexpected per-agent stub call');
  source = source.replace(perAgent, 'containerPath:`${p5}/auth.json`,content:p4(u?.accountId)');
  const shared = 'content:i?p3:p4(),authMode:i?';
  if (source.split(shared).length !== 2) throw new Error('Unexpected shared stub call');
  // Workspace-wide stubs must not arbitrarily select among different accounts.
  source = source.replace(shared,
    'content:i?p3:p4(r.length>0&&r.every(e=>e.metadata?.accountId===r[0].metadata?.accountId)?r[0].metadata?.accountId:undefined),authMode:i?');
  return source;
}

module.exports = { patch };
if (require.main === module) {
  const file = process.argv[2];
  fs.writeFileSync(file, patch(fs.readFileSync(file, 'utf8')));
}

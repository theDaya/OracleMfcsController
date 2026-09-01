/*
 * Static checks for folder "09 - Flow: Create Style with SKUs".
 *
 *     node postman/verify-flow.js
 *
 * No dependencies, no network, creates nothing. Run it after editing the collection.
 *
 * The behaviour checks exist because syntax checking is not enough. The first version of
 * this folder read `pm.response.ok`, which is a Fetch API property that Postman's response
 * object does not have. It parsed fine, and then halted the run after every request -
 * including ones that returned HTTP 200 and passed their own assertions. Anything that
 * decides whether to halt or retry is worth executing against a fake response, not just
 * parsing.
 */
const fs = require('fs');
const path = require('path');

const COL = path.join(__dirname, 'OracleMFCS.postman_collection.json');
const col = JSON.parse(fs.readFileSync(COL, 'utf8'));
const folder = col.item.find((f) => f.name.startsWith('09 - Flow'));
if (!folder) {
  console.error('Folder "09 - Flow: Create Style with SKUs" is not in the collection.');
  process.exit(1);
}

const PARENT = '100000180';
const C1 = '100000198';
const C2 = '100000201';
const fails = [];

/* ------------------------------------------------------------------ structure */

const declared = new Set(col.variable.map((v) => v.key));
// Set by the folder's own scripts at run time rather than declared with a value.
['parentItem', 'childItem1', 'childItem2', 'correlationId', 'accessToken'].forEach((k) =>
  declared.add(k));

const sample = {
  parentItem: PARENT, childItem1: C1, childItem2: C2, correlationId: 'c', accessToken: 't',
  flowDescription: 'Postman flow 20260901',
};
const value = (k) => {
  if (k in sample) return sample[k];
  const v = col.variable.find((x) => x.key === k);
  return v && v.value ? v.value : '1';
};

let bodies = 0;
for (const item of folder.item) {
  for (const token of JSON.stringify(item.request).match(/\{\{(\w+)\}\}/g) || []) {
    const k = token.slice(2, -2);
    if (!declared.has(k)) fails.push(`${item.name}: uses undeclared variable {{${k}}}`);
  }
  const raw = item.request.body && item.request.body.raw;
  if (raw) {
    bodies++;
    const resolved = raw.replace(/\{\{(\w+)\}\}/g, (_, k) => value(k));
    try {
      JSON.parse(resolved);
    } catch (e) {
      fails.push(`${item.name}: body is not valid JSON once variables resolve - ${e.message}`);
    }
  }
}

/* ------------------------------------------------------------------ behaviour */

// Assertion outcomes are not what these checks are about, so pm.expect returns a chain
// that swallows anything. Only setNextRequest and variable writes are observed.
const anyChain = new Proxy(function () { return anyChain; }, {
  get: () => anyChain,
  apply: () => anyChain,
});

function healthyBody(name) {
  // The status feed carries a status per row, and none at the top level.
  if (name.startsWith('00')) return { items: [{ requestId: 'x', status: 'COMPLETED' }] };
  if (/^0[123]/.test(name)) return { items: [{ item: PARENT, itemNumberType: 'ITEM' }] };
  if (name.startsWith('10')) return detail('W');
  if (name.startsWith('12')) return detail('A');
  return { status: 'SUCCESS' };
}

function detail(status) {
  return [
    { item: PARENT, status },
    { item: C1, itemParent: PARENT, diff1: '08610', diff2: '070', status },
    { item: C2, itemParent: PARENT, diff1: '08610', diff2: '080', status },
  ];
}

function run(item, code, body, attempt) {
  const vars = {
    parentItem: PARENT, childItem1: C1, childItem2: C2,
    size1Diff: '070', size2Diff: '080', colourDiff: '08610',
    readBackAttempt: attempt || 0,
  };
  const routed = [];
  const pm = {
    info: { requestName: item.name },
    response: {
      code,
      // Deliberately absent, mirroring the real sandbox.
      ok: undefined,
      json: () => { if (body === null) throw new Error('not json'); return body; },
      text: () => JSON.stringify(body),
      to: { have: { status: () => {} } },
    },
    test: (n, fn) => { try { fn(); } catch (e) { /* not under test here */ } },
    expect: () => anyChain,
    collectionVariables: { get: (k) => vars[k], set: (k, v) => { vars[k] = v; } },
  };
  const quiet = { log: () => {}, warn: () => {}, error: () => {} };
  const src = item.event.find((e) => e.listen === 'test').script.exec.join('\n');
  // A syntax error surfaces here, so this covers parsing as well.
  new Function('pm', 'postman', 'console', src)(
    pm, { setNextRequest: (t) => routed.push(t) }, quiet);
  return { halted: routed.includes(null), retried: routed.includes(item.name), vars };
}

let scripts = 0;
for (const item of folder.item) {
  const name = item.name;
  scripts++;

  const good = run(item, 200, healthyBody(name));
  if (good.halted) fails.push(`${name}: halts the run on a healthy 200 response`);
  if (good.retried) fails.push(`${name}: retries even though the data is complete`);

  if (!run(item, 400, { status: 'ERROR', message: 'Batch Running Indicator is ON' }).halted) {
    fails.push(`${name}: does not halt on HTTP 400`);
  }
  if (!run(item, 401, null).halted) fails.push(`${name}: does not halt on HTTP 401`);

  // A write answered 200 with a non-SUCCESS body is still a failure. The read-backs
  // judge the rows instead, and the preflight's feed has no top-level status.
  if (!/^(00|10|12)/.test(name) && !run(item, 200, { status: 'ERROR' }).halted) {
    fails.push(`${name}: does not halt on HTTP 200 with status ERROR`);
  }
}

if (run(folder.item[1], 200, { items: [{ item: PARENT }] }).vars.parentItem !== PARENT) {
  fails.push('01: does not publish the reserved number into {{parentItem}}');
}

// Feed lag must be retried; exhausted retries must give up rather than loop forever.
const thin = [{ item: PARENT, status: 'W' }];
const lag = run(folder.item[10], 200, thin, 0);
if (!lag.retried) fails.push('10: does not retry while the children are not visible yet');
if (lag.halted) fails.push('10: halts instead of retrying on feed lag');

const spent = run(folder.item[10], 200, thin, 3);
if (spent.retried) fails.push('10: still retrying after the third attempt');
if (!spent.halted) fails.push('10: does not halt once the retries are spent');
if (run(folder.item[12], 200, thin, 3).retried) {
  fails.push('12: still retrying after the third attempt');
}

/* --------------------------------------------------------------------- report */

console.log(`requests           : ${folder.item.length}`);
console.log(`bodies JSON-checked: ${bodies}`);
console.log(`scripts executed   : ${scripts}`);

if (fails.length) {
  console.log('\nFAILURES:');
  fails.forEach((f) => console.log('  - ' + f));
  process.exit(1);
}
console.log('\nALL CHECKS PASSED');

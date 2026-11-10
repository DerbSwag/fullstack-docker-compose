import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
const base = 'http://127.0.0.1:3000';
const expectedSeeds = ['nattawat','anan','benjamas','chaiwat','daranee','ekkachai','fahlada','kittipong','manatsawee','pongsakorn'];
// Deliberately fixed container-local endpoints; host ports belong to start.sh.
async function request(fetcher, path, options = {}, status = 200) {
  const response = await fetcher(base + path, { ...options, signal: AbortSignal.timeout(10000) });
  assert.equal(response.status, status, path);
  return response.json();
}
const json = (method, body) => ({ method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
function assertSeeds(users, fresh) {
  assert(Array.isArray(users));
  assert.equal(expectedSeeds.length, 10);
  for (const email of expectedSeeds) assert.equal(users.filter(u => u.email === email + '@example.com').length, 1, email);
  if (fresh) assert.equal(users.length, 10, 'fresh initialization must contain exactly ten rows');
}
async function cleanup(fetcher, email) {
  let failure;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const users = await request(fetcher, '/api/users');
      assert(Array.isArray(users));
      for (const row of users.filter(u => u.email === email)) {
        assert(Number.isSafeInteger(row.id) && row.id > 0, 'refusing cleanup with an invalid owned ID');
        await request(fetcher, '/api/users/' + row.id, { method: 'DELETE' });
      }
      assert(!(await request(fetcher, '/api/users')).some(u => u.email === email), 'test row still exists');
      return;
    } catch (error) {
      failure = error;
      if (attempt < 2) await new Promise(resolve => setTimeout(resolve, 50));
    }
  }
  throw failure;
}
async function crud(fetcher) {
  const email = 'codex-' + randomUUID() + '@example.invalid';
  let operationFailure;
  try {
    await request(fetcher, '/api/users', json('POST', {}), 400);
    const created = await request(fetcher, '/api/users', json('POST', { name: 'Codex integration test', email }), 201);
    assert.equal(created.email, email);
    assert(Number.isSafeInteger(created.id) && created.id > 0);
    assert((await request(fetcher, '/api/users')).some(u => u.id === created.id && u.email === email));
    const updated = await request(fetcher, '/api/users/' + created.id, json('PUT', { name: 'Codex updated', email }));
    assert.equal(updated.name, 'Codex updated');
    assert.equal(updated.email, email);
    assert((await request(fetcher, '/api/users')).some(u => u.id === created.id && u.name === 'Codex updated'));
    await request(fetcher, '/api/users/' + created.id, { method: 'DELETE' });
    assert(!(await request(fetcher, '/api/users')).some(u => u.email === email));
  } catch (error) {
    operationFailure = error;
  }
  // Always find ownership by the UUID email, including when POST committed but
  // its status, JSON body, network response or subsequent assertion failed.
  try {
    await cleanup(fetcher, email);
  } catch (error) {
    throw new AggregateError([operationFailure, error].filter(Boolean), 'CRUD/cleanup failed; preserve evidence and inspect the unique test email: ' + email);
  }
  if (operationFailure) throw operationFailure;
}
async function selfTest() {
  for (const scenario of ['success','post-status','post-json','post-assertion','post-network-error','cleanup-failure']) {
    let rows = [{ id: 1, name: 'Persistent user', email: 'persistent@example.invalid' }];
    const deleted = [];
    let committed = false;
    const fetcher = async (url, options) => {
      const path = new URL(url).pathname;
      const method = options.method || 'GET';
      if (method === 'POST') {
        const body = JSON.parse(options.body);
        if (!body.email) return new Response('{}', { status: 400 });
        const row = { id: 2, ...body }; rows.push(row); committed = true;
        if (scenario === 'post-network-error') throw new Error('response lost after commit');
        if (scenario === 'post-json') return new Response('{invalid', { status: 201 });
        return new Response(JSON.stringify(scenario === 'post-assertion' ? { ...row, email: 'wrong' } : row), { status: scenario === 'post-status' ? 500 : 201 });
      }
      if (method === 'GET') {
        if (scenario === 'cleanup-failure' && committed) return new Response('{}', { status: 503 });
        return new Response(JSON.stringify(rows));
      }
      const id = Number(path.split('/').at(-1));
      assert.equal(id, 2, 'must never change the persistent row');
      if (method === 'PUT') {
        Object.assign(rows.find(u => u.id === id), JSON.parse(options.body));
        return new Response(JSON.stringify(rows.find(u => u.id === id)));
      }
      assert.equal(method, 'DELETE');
      deleted.push(id); rows = rows.filter(u => u.id !== id);
      return new Response('{}');
    };
    let failure;
    try { await crud(fetcher); } catch (error) { failure = error; }
    assert.deepEqual(rows[0], { id: 1, name: 'Persistent user', email: 'persistent@example.invalid' });
    if (scenario === 'cleanup-failure') {
      assert(failure instanceof AggregateError);
      assert(failure.errors.length >= 2);
    } else {
      assert.equal(rows.length, 1, scenario);
      assert(deleted.every(id => id === 2));
      if (scenario === 'success') assert.equal(failure, undefined);
      else assert(failure, scenario + ' must preserve the original error');
    }
  }
  const users = expectedSeeds.map(email => ({ email: email + '@example.com' }));
  assertSeeds(users, true);
  assertSeeds([...users, { email: 'persistent@example.invalid' }], false);
  assert.throws(() => assertSeeds([...users, { email: 'persistent@example.invalid' }], true));
  console.log('PASS: cleanup after status/JSON/assertion/network failures; preserves original/cleanup errors and unrelated rows; fresh/persistent seed policies');
}
async function main() {
  const args = new Set(process.argv.slice(2));
  assert(args.size === process.argv.slice(2).length && [...args].every(x => ['--self-test','--seeds-only','--fresh'].includes(x)), 'unsupported test arguments');
  if (args.has('--self-test')) {
    assert.equal(args.size, 1); await selfTest(); return;
  }
  const users = await request(fetch, '/api/users');
  assertSeeds(users, args.has('--fresh'));
  if (args.has('--seeds-only')) {
    console.log(args.has('--fresh') ? 'PASS: new volume initialized with exactly ten seed users' : 'PASS: seed users present; persistent extra rows allowed');
    return;
  }
  const direct = await fetch('http://backend:3001/health', { signal: AbortSignal.timeout(10000) });
  assert.equal(direct.status, 200);
  assert.equal((await direct.json()).database, 'connected');
  const page = await fetch(base, { signal: AbortSignal.timeout(10000) });
  assert.equal(page.status, 200); assert.match(await page.text(), /id="root"/);
  assert.equal((await request(fetch, '/api/health')).database, 'connected');
  await crud(fetch);
  console.log('PASS: health, React entrypoint, Vite proxy, seed presence and owned CRUD cleanup');
}
main().catch(error => {
  console.error(error);
  if (error instanceof AggregateError) for (const cause of error.errors) console.error('Cause:', cause);
  process.exitCode = 1;
});

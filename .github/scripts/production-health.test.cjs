const { test } = require('node:test');
const assert = require('node:assert/strict');
const { origin, checkHealth } = require('./check-production-health.cjs');
test('missing, credential-bearing, non-HTTPS and non-origin configuration fails closed', () => {
  for (const value of ['', undefined, 'http://example.com', 'https://user:secret@example.com', 'https://example.com/path', 'https://example.com/?secret=x'])
    assert.throws(() => origin(value));
  assert.equal(origin('https://example.com/'), 'https://example.com');
});
test('checks both routes independently and requires actual DB health', async () => {
  const calls=[];
  const results=await checkHealth('https://example.com', async (url, options) => {
    calls.push(url); assert.equal(options.redirect,'error'); assert.ok(options.signal);
    return {ok:true,json:async()=>({ok:true,db:false})};
  });
  assert.equal(calls.length,2); assert.deepEqual(results.map(x=>x.ok),[true,false]);
});
test('failures and malformed payloads cannot become skipped success', async () => {
  let count=0;
  const result=await checkHealth('https://example.com',async()=>{
    if (++count===1) throw new Error('private upstream detail');
    return {ok:true,json:async()=>{throw new Error('private body')}};
  });
  assert.deepEqual(result.map(x=>x.ok),[false,false]);
});
test('healthy liveness and database payloads pass',async()=>{
 const result=await checkHealth('https://example.com',async()=>({ok:true,json:async()=>({ok:true,db:true})}));
 assert.ok(result.every(x=>x.ok));
});

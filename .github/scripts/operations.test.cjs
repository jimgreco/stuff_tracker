const {test}=require('node:test');
const assert=require('node:assert/strict');
const {notify}=require('./notify-operations.cjs');
test('unconfigured alert fails explicitly without sending',async()=>{
 let calls=0; await assert.rejects(notify({},async()=>{calls++}),/not configured/); assert.equal(calls,0);
});
test('only HTTPS destinations without embedded credentials are allowed',async()=>{
 for (const url of ['http://example.com','https://user:secret@example.com','#token'])
   await assert.rejects(notify({WEBHOOK_URL:url},async()=>{throw new Error('must not call')}));
});
test('synthetic delivery is bounded, rejects redirects, and contains no secrets',async()=>{
 const env={WEBHOOK_URL:'https://example.com/private-token',GITHUB_REPOSITORY:'example/repo',GITHUB_RUN_ID:'123',ALERT_TITLE:'Synthetic',ALERT_SUMMARY:'freshness=failure'};
 let calls=0; await notify(env,async(url,options)=>{
   calls++; assert.equal(options.redirect,'error'); assert.ok(options.signal);
   assert.equal(options.method,'POST'); assert.ok(!options.body.includes('private-token'));
   assert.equal(JSON.parse(options.body).run_url,'https://github.com/example/repo/actions/runs/123');
   return {ok:true};
 }); assert.equal(calls,1);
});
test('provider failures expose only a fixed error and never retry a send',async()=>{
 let calls=0;
 await assert.rejects(notify({WEBHOOK_URL:'https://example.com/private-token'},async()=>{calls++;throw new Error('private-token')}),error=>error.message==='Operations alert delivery failed');
 assert.equal(calls,1);
});

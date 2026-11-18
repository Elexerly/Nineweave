import assert from 'node:assert/strict';
const base='https://br-still-mode-bdsyavce-lexerlytest.compute.c-8.us-east-2.aws.neon.tech/api/nineweave';
async function call(method,path,token,body){const r=await fetch(base+path,{method,headers:{'Content-Type':'application/json',Origin:'https://elexerly.github.io',...(token?{Authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body)});const data=await r.json();if(r.status>=500)console.log({status:r.status,error:data});return{status:r.status,data};}
const a=await call('POST','/auth/device',null,{}),b=await call('POST','/auth/device',null,{});
assert.equal(a.status,201);assert.equal(b.status,201);
for(const [code,id] of [['pRoF26','professor_gilt'],['jB2026','jb_rocker'],['n2026','nick']]){const r=await call('POST','/me/unlocks',a.data.token,{code});assert.equal(r.status,200);assert.equal(r.data.unlock.id,id);}
assert.equal((await call('POST','/me/unlocks',a.data.token,{code:'JB2026'})).data.already_owned,true);
assert.deepEqual((await call('GET','/me',a.data.token)).data.unlocked_heroes,['jb_rocker','nick','professor_gilt']);
assert.deepEqual((await call('GET','/me',b.data.token)).data.unlocked_heroes,[]);
assert.equal((await call('PATCH','/me',b.data.token,{last_hero_id:'jb_rocker'})).status,403);
assert.equal((await call('PATCH','/me',a.data.token,{last_hero_id:'jb_rocker'})).status,200);
const roster=(await call('GET','/heroes')).data;assert.equal(roster.heroes.length,32);assert.deepEqual(roster.secret_heroes,['nick','professor_gilt','jb_rocker']);
console.log('PASS hosted SQL: account registration, all 3 mixed-case codes, idempotency, saved ownership, account isolation, lock guard, hero selection, 32+3 catalog. No credentials printed.');

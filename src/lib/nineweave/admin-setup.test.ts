import { after, before, beforeEach, describe, it, mock } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { scryptSync } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { handleAdminSetup, verifyAdminPassphrase, type AdminOptions } from './admin-api.ts';
import { adminSetupPage } from './admin-page.ts';
import { createConfigStore, resolveNineweaveDatabaseUrl, resolveResendKey } from './config.ts';
import { migrateAdminTarget } from './admin-migrations.ts';
import { pgliteDb, type Db } from './store.ts';
import type { EmailMessage } from './mailer.ts';

const passphrase = 'synthetic-test-only-passphrase';
const salt = Buffer.alloc(16, 7);
const hash = `scrypt$${salt.toString('hex')}$${scryptSync(passphrase, salt, 32, { N:16384, r:8, p:1 }).toString('hex')}`;
const fakeUrl = 'postgresql://fixture:fixture_password@neon.invalid/fixture';
const fakeKey = 're_synthetic_fixture_6789';
const migrationDir = join(import.meta.dirname, '../../../migrations');
const migrations = Object.fromEntries(readdirSync(migrationDir).filter(name => name.endsWith('.sql')).map(name => [name, readFileSync(join(migrationDir, name), 'utf8')]));
let pg: PGlite;
let targetPg: PGlite;
let db: Db;
let target: Db;
let now = 0;
let options: AdminOptions;
let sent: EmailMessage[];
let connections: number;

before(async () => {
  pg = new PGlite({ parsers: {20:Number} });
  targetPg = new PGlite({ parsers: {20:Number} });
  await Promise.all([pg.waitReady, targetPg.waitReady]);
  db = pgliteDb(pg); target = pgliteDb(targetPg);
  await migrateAdminTarget(db, migrations);
});
after(async () => { await Promise.all([pg.close(), targetPg.close()]); });
beforeEach(async () => {
  await pg.exec('truncate nw_admin_config, nw_players cascade');
  now = Date.parse('2026-11-15T12:00:00Z'); sent = []; connections = 0;
  const config = createConfigStore(async () => db, () => now);
  options = {
    enabled:true, hash, builtin:async () => db, config,
    active:async () => (await config.read()).nineweave_database_url ? target : db,
    connect:async () => { connections++; return target; },
    migrations, env:{ DATABASE_URL:'postgresql://fixture:fixture@builtin.invalid/fixture' },
    now:() => now, mailer:key => key ? async message => { sent.push(message); } : null,
  };
});

function call(body?: Record<string, unknown>, credential = passphrase, ip = '192.0.2.1') {
  return handleAdminSetup(new Request('https://nineweave.invalid/api/nineweave/admin/setup', {
    method:body ? 'POST' : 'GET',
    headers:{ 'content-type':'application/json', 'x-nineweave-admin-passphrase':credential, 'x-forwarded-for':ip },
    body:body ? JSON.stringify({ passphrase:credential, ...body }) : undefined,
  }), options);
}

describe('temporary admin setup', () => {
  it('flag off and UNSET return 404 for page and all API requests without touching DB', async () => {
    for (const [enabled, stored] of [[false, hash], [true, 'UNSET']] as const) {
      options.enabled = enabled; options.hash = stored;
      options.builtin = async () => { throw new Error('must not connect'); };
      assert.equal(adminSetupPage('secret form', enabled, stored).status, 404);
      assert.equal((await call()).status, 404);
      assert.equal((await call({ resend_api_key:fakeKey })).status, 404);
    }
  });
  it('valid page has no-store and a malformed hash is unavailable', async () => {
    const page = adminSetupPage('<h1>Setup</h1>', true, hash);
    assert.equal(page.status, 200); assert.equal(page.headers.get('cache-control'), 'no-store');
    assert.equal(await verifyAdminPassphrase(passphrase, 'scrypt$bad$bad'), false);
    assert.equal(await verifyAdminPassphrase(passphrase, hash), true);
    assert.equal(await verifyAdminPassphrase('wrong', hash), false);
  });
  it('allows five failed attempts per IP, blocks the sixth and expires the rolling window', async () => {
    for (let i=0;i<5;i++) assert.equal((await call(undefined, 'wrong')).status, 401);
    const blocked = await call(); assert.equal(blocked.status, 429);
    assert.equal(blocked.headers.get('retry-after'), '900');
    now += 900_001; assert.equal((await call()).status, 200);
  });
  it('enforces twenty global failures across instances and rolling-hour expiry', async () => {
    for (let i=0;i<20;i++) assert.equal((await call(undefined, 'wrong', `192.0.2.${i+1}`)).status, 401);
    // New store/handler instance shares the DB-backed budget.
    options.config = createConfigStore(async () => db, () => now);
    assert.equal((await call(undefined, passphrase, '192.0.2.99')).status, 429);
    now += 3_600_001;
    assert.equal((await call(undefined, passphrase, '192.0.2.99')).status, 200);
  });
  it('serializes concurrent failures and does not charge successful authentication', async () => {
    const results = await Promise.all(Array.from({length:9}, () => call(undefined, 'wrong')));
    assert.equal(results.filter(r => r.status === 401).length, 5);
    assert.equal(results.filter(r => r.status === 429).length, 4);
    for (let i=0;i<8;i++) assert.equal((await call(undefined, passphrase, '192.0.2.2')).status, 200);
  });
  it('resolves env > saved config > host/none, with a sixty-second cache', async () => {
    const store = options.config;
    assert.equal(await resolveNineweaveDatabaseUrl(options.env, store), options.env.DATABASE_URL);
    assert.equal(await resolveResendKey({}, store), undefined);
    await store.save({nineweave_database_url:fakeUrl, resend_api_key:fakeKey});
    assert.equal(await resolveNineweaveDatabaseUrl(options.env, store), fakeUrl);
    assert.equal(await resolveResendKey({}, store), fakeKey);
    assert.equal(await resolveNineweaveDatabaseUrl({NINEWEAVE_DATABASE_URL:'postgres://override:fixture@override.invalid/db'}, store), 'postgres://override:fixture@override.invalid/db');
    assert.equal(await resolveResendKey({NINEWEAVE_RESEND_API_KEY:'env-fixture-key'}, store), 'env-fixture-key');
    await db.query("update nw_admin_config set value = 'replacement-fixture' where key = 'resend_api_key'");
    assert.equal(await resolveResendKey({}, store), fakeKey);
    now += 60_001;
    assert.equal(await resolveResendKey({}, store), 'replacement-fixture');
  });
  it('migrates Neon before saving, records files once, excludes auth and copies no players', async () => {
    await pg.query("insert into nw_players (id,token_hash,screen_name) values ('existing','existing','RealPlayer')");
    options.migrations = {...migrations, '/migrations/auth/0001_auth.sql':'INVALID AUTH SQL'};
    assert.equal((await call({nineweave_database_url:fakeUrl})).status, 200);
    assert.equal(connections, 1);
    assert.equal((await target.query('select id from nw_players')).length, 0);
    assert.equal((await target.query('select name from _migrations')).length, Object.keys(migrations).length);
    assert.equal((await call({nineweave_database_url:fakeUrl})).status, 200);
    assert.equal((await target.query('select name from _migrations')).length, Object.keys(migrations).length);
    assert.equal((await db.query('select id from nw_players')).length, 1);
    assert.equal((await db.query("select key from nw_admin_config where key = 'nineweave_database_url'")).length, 1);
    assert.equal((await target.query('select key from nw_admin_config')).length, 0);
  });
  it('does not save either setting after connection/migration errors, and redacts all errors/logs', async () => {
    const logs: unknown[][] = [];
    const spies = ['log','warn','error'].map(name => mock.method(console, name as 'log', (...args:unknown[]) => logs.push(args)));
    try {
      options.connect = async () => { throw new Error(fakeUrl + fakeKey + passphrase); };
      const response = await call({nineweave_database_url:fakeUrl, resend_api_key:fakeKey});
      assert.equal(response.status, 503);
      const text = await response.text();
      for (const secret of [fakeUrl,fakeKey,passphrase]) assert.ok(!text.includes(secret) && !JSON.stringify(logs).includes(secret));
      assert.equal((await db.query("select key from nw_admin_config where key in ('nineweave_database_url','resend_api_key')")).length, 0);
    } finally { spies.forEach(spy => spy.mock.restore()); }
  });
  it('rolls back the failing migration and never saves an unverified target', async () => {
    options.migrations = {'9999_failure.sql':'create table rollback_probe (id int); select * from nonexistent_fixture_table;'};
    const response = await call({nineweave_database_url:fakeUrl});
    assert.equal(response.status, 503);
    const [row] = await target.query<{table:string|null}>("select to_regclass('rollback_probe')::text as table");
    assert.equal(row.table, null);
    assert.equal((await db.query("select key from nw_admin_config where key = 'nineweave_database_url'")).length, 0);
  });
  it('saves fields separately, masks status and never returns submitted secrets', async () => {
    assert.equal((await call({resend_api_key:fakeKey})).status, 200);
    assert.equal(connections, 0);
    const response = await call(); const text = await response.text(); const result = JSON.parse(text);
    assert.equal(result.database, 'built-in'); assert.equal(result.neon_host, null);
    assert.equal(result.resend_key_last4, '6789'); assert.equal(result.resend_key_set, true);
    assert.ok(Array.isArray(result.migrations));
    for (const secret of [fakeUrl,fakeKey,passphrase]) assert.ok(!text.includes(secret));
    await options.config.save({nineweave_database_url:fakeUrl});
    const neon = await (await call()).json(); assert.equal(neon.database, 'Neon'); assert.equal(neon.neon_host, 'neon.invalid');
  });
  it('test mail is fixed-recipient, optional key yields 503, mailer exceptions are sanitized', async () => {
    assert.equal((await call({action:'send_test_email'})).status, 503);
    await options.config.save({resend_api_key:fakeKey});
    assert.equal((await call({action:'send_test_email', to:'ignored@example.invalid'})).status, 200);
    assert.equal(sent.length,1); assert.equal(sent[0].to,'patrick@probeyahngroup.com');
    options.mailer = () => async () => { throw new Error(fakeKey); };
    const failed = await call({action:'send_test_email'}); assert.equal(failed.status,503);
    assert.ok(!(await failed.text()).includes(fakeKey));
  });
  it('rejects invalid URLs, malformed bodies and cross-origin attempts', async () => {
    for (const value of ['https://example.invalid/db','garbage','postgresql:///']) assert.equal((await call({nineweave_database_url:value})).status,400);
    assert.equal(connections,0);
    assert.equal((await call({resend_api_key:42})).status,400);
    const foreign = new Request('https://nineweave.invalid/api/nineweave/admin/setup', {headers:{origin:'https://foreign.invalid'}});
    assert.equal((await handleAdminSetup(foreign, options)).status,403);
    const querySecret = new Request('https://nineweave.invalid/api/nineweave/admin/setup?passphrase=ignored');
    assert.equal((await handleAdminSetup(querySecret, options)).status,401);
  });
  it('clears only named test accounts on the ACTIVE DB with counts and dependent rows', async () => {
    await migrateAdminTarget(target, migrations);
    await targetPg.exec('truncate nw_players cascade');
    await target.query("insert into nw_players (id,token_hash,screen_name) values ('test1','t1','T4cAlpha'), ('test2','t2','NWSmokeBeta'), ('real','r','RealPlayer'), ('near','n','xT4cPlayer')");
    await target.query("insert into nw_email_challenges (id,player_id,email,purpose,code_hash,expires_at) values ('ec_fixture','test1','fixture@example.invalid','verify','fixture',now())");
    await target.query("insert into nw_blocks (blocker_id,blocked_id) values ('test1','real')");
    await target.query("insert into nw_tournaments (id,code,status,size,host_player_id,starts_at,rev) values ('t_fixture','TAAAAA','registering',4,'real',now(),'rev')");
    await target.query("insert into nw_tournament_players (tournament_id,player_id,name,hero) values ('t_fixture','test1','T4cAlpha','fixture'), ('t_fixture','real','RealPlayer','fixture')");
    await pg.query("insert into nw_players (id,token_hash,screen_name) values ('builtin','b','T4cBuiltin')");
    await options.config.save({nineweave_database_url:fakeUrl});
    const response = await call({action:'clear_test_accounts'});
    assert.equal(response.status,200);
    const {cleared} = await response.json();
    assert.equal(cleared.players,2); assert.equal(cleared.email_challenges,1); assert.equal(cleared.blocks,1);
    assert.equal(cleared.tournaments,1); assert.equal(cleared.tournament_players,2);
    assert.deepEqual((await target.query<{id:string}>('select id from nw_players order by id')).map(r => r.id), ['near','real']);
    assert.equal((await db.query('select id from nw_players')).length,1);
    const again = await (await call({action:'clear_test_accounts'})).json(); assert.equal(again.cleared.players,0);
  });
});

it('admin same-site check works behind a proxy with an internal request.url', async () => {
  const { sameSiteRequest } = await import('./admin-api.ts');
  const mk = (h: Record<string,string>) => new Request('http://127.0.0.1:3000/api/nineweave/admin/setup', { method: 'POST', headers: h });
  assert.equal(sameSiteRequest(mk({ origin: 'https://nineweave.grok.me', 'sec-fetch-site': 'same-origin' })), true);
  assert.equal(sameSiteRequest(mk({ origin: 'https://other.example', host: 'other.example.internal' })), false);
  assert.equal(sameSiteRequest(mk({ origin: 'https://proxy.example', 'x-forwarded-host': 'proxy.example' })), true);
  assert.equal(sameSiteRequest(mk({ origin: 'https://evil.example', 'sec-fetch-site': 'cross-site' })), false);
  assert.equal(sameSiteRequest(mk({})), true);
});

import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { PGlite } from "@electric-sql/pglite";
import { handleNineweaveRequest } from "./api.ts";
import { createService, type Service } from "./service.ts";
import { pgliteDb } from "./store.ts";
import { tournamentSeatToken, type RoomRow } from "./rooms.ts";
import { Rules } from "./rules.ts";
import { hashToken } from "./security.ts";
let pg: PGlite; let svc: Service;
before(async () => {
  pg = new PGlite({ parsers: { 20: Number } }); await pg.waitReady;
  const dir = join(import.meta.dirname,"../../../migrations");
  for (const file of readdirSync(dir).filter(f=>f.endsWith(".sql")).sort()) await pg.exec(readFileSync(join(dir,file),"utf8"));
});
after(async()=>pg.close());
beforeEach(async()=>{
  await pg.exec("truncate nw_players, nw_rooms, nw_tournaments restart identity cascade");
  svc=createService({db:pgliteDb(pg), limits:{device:1000,write:1000}, mailer:null});
});
async function call(method:string,path:string,token?:string,body?:unknown){
  const res=await handleNineweaveRequest(svc,new Request("http://localhost/api/nineweave"+path,{method,headers:token?{Authorization:"Bearer "+token}:{},body:body===undefined?undefined:JSON.stringify(body)}));
  return {status:res.status,body:await res.json()};
}
async function device(name:string){const r=await call("POST","/auth/device",undefined,{screen_name:name});assert.equal(r.status,201);return r.body;}
const confirmation={confirm:"DELETE MY ACCOUNT"};
async function fixture(){
  const a=await device("Old Identity"), b=await device("Opponent");
  await pg.query("update nw_players set email='old@example.com',email_verified_at=now(),matches_won=3 where id=$1",[a.player_id]);
  await pg.query("update nw_players set matches_won=7,matches_lost=2 where id=$1",[b.player_id]);
  await pg.query(`insert into nw_rooms(id,code,status,x_slot,state,rev,a_player_id,a_name,a_hero,a_token_hash,a_seen_at,b_player_id,b_name,b_hero,b_token_hash,b_seen_at)
    values('r_test','ABCDE','finished','a','{}','rev',$1,'Old Identity','vesper_vale',$3,now(),$2,'Opponent','auric_rex',$4,now())`,[a.player_id,b.player_id,hashToken("nws_old"),hashToken("nws_opponent")]);
  await pg.query(`insert into nw_matches(room_id,round,x_player_id,o_player_id,x_name,o_name,x_hero,o_hero,result,end_reason,x_boards,o_boards,moves)
    values('r_test',1,$1,$2,'Old Identity','Opponent','vesper_vale','auric_rex','o','win',1,3,45)`,[a.player_id,b.player_id]);
  await pg.query(`insert into nw_tournaments(id,code,status,size,host_player_id,starts_at,champion_player_id,champion_name,rev)
    values('t_test','TABCDE','finished',4,$1,now(),$1,'Old Identity','rev')`,[a.player_id]);
  await pg.query("insert into nw_tournament_players(tournament_id,player_id,name,hero) values('t_test',$1,'Old Identity','vesper_vale')",[a.player_id]);
  await pg.query("insert into nw_tournament_matches(tournament_id,round,slot,a_player_id,b_player_id,status,winner) values('t_test',1,1,$1,$2,'done','b')",[a.player_id,b.player_id]);
  await pg.query("insert into nw_chat(room_id,round,seat,slot,player_id,name,text) values('r_test',1,1,'a',$1,'Old Identity','private words'),('r_test',1,2,'b',$2,'Opponent','hello')",[a.player_id,b.player_id]);
  await pg.query("insert into nw_blocks(blocker_id,blocked_id) values($1,$2)",[a.player_id,b.player_id]);
  await pg.query(`insert into nw_reports(reporter_id,reported_id,reported_name,room_code,reason,note,chat_snapshot) values($1,$2,'Opponent','ABCDE','other','identifying note','[{"text":"private words"}]'),($2,$1,'Old Identity','ABCDE','other','another note','[]')`,[a.player_id,b.player_id]);
  await pg.query("insert into nw_email_challenges(id,player_id,email,purpose,code_hash,expires_at) values('ec_test',$1,'old@example.com','verify','secret',now())",[a.player_id]);
  return {a,b};
}
async function rows(table:string){return (await pg.query(`select * from ${table}`)).rows as any[];}
describe("own account deletion",()=>{
  it("requires own valid device authentication and exact explicit confirmation",async()=>{
    const a=await device("Keep Me");
    assert.equal((await call("DELETE","/me",undefined,confirmation)).status,401);
    assert.equal((await call("DELETE","/me","nws_seat",confirmation)).status,401);
    assert.equal((await call("DELETE","/me",a.token,{})).status,400);
    assert.equal((await call("DELETE","/me",a.token,{...confirmation,player_id:"other"})).status,400);
    assert.equal((await rows("nw_players")).length,1);
  });
  it("erases identifying account data and reports while preserving unlinked shared results/opponent stats",async()=>{
    const {a,b}=await fixture();
    const r=await call("DELETE","/me",a.token,confirmation);assert.equal(r.status,200,JSON.stringify(r.body));
    assert.equal((await call("GET","/me",a.token)).status,401);
    assert.equal((await call("DELETE","/me",a.token,confirmation)).status,401);
    const players=await rows("nw_players");assert.equal(players.length,1);assert.equal(players[0].id,b.player_id);assert.equal(players[0].matches_won,7);assert.equal(players[0].matches_lost,2);
    for(const table of ["nw_email_challenges","nw_blocks","nw_reports","nw_tournament_players"])assert.equal((await rows(table)).length,0,table);
    const chat=await rows("nw_chat");assert.equal(chat.length,1);assert.equal(chat[0].player_id,b.player_id);
    const room=(await rows("nw_rooms"))[0];assert.equal(room.a_player_id,null);assert.equal(room.a_name,"####");assert.notEqual(room.a_token_hash,hashToken("nws_old"));assert.equal(room.b_token_hash,hashToken("nws_opponent"));
    const match=(await rows("nw_matches"))[0];assert.equal(match.x_player_id,null);assert.equal(match.x_name,"####");assert.equal(match.o_player_id,b.player_id);assert.equal(match.result,"o");assert.equal(match.o_name,"Opponent");
    const t=(await rows("nw_tournaments"))[0];assert.equal(t.host_player_id,null);assert.equal(t.champion_player_id,null);assert.equal(t.champion_name,"####");
    const tm=(await rows("nw_tournament_matches"))[0];assert.equal(tm.a_player_id,null);assert.equal(tm.b_player_id,b.player_id);assert.equal(tm.winner,"b");
    const replacement=await device("Old Identity");
    assert.equal(replacement.player.screen_name,"Old Identity");
    assert.equal((await call("DELETE","/me",b.token,confirmation)).status,200);
    const both=(await rows("nw_matches"))[0];
    assert.equal(both.x_name,"####");assert.equal(both.o_name,"####");assert.equal(both.o_player_id,null);assert.equal(both.result,"o");
    assert.equal((await rows("nw_rooms"))[0].b_token_hash,null);
    assert.equal((await rows("nw_players"))[0].id,replacement.player_id);
  });
  for(const status of ["waiting","active"]){
    it(`blocks ${status} room without modifying data`,async()=>{
      const {a}=await fixture();await pg.query("update nw_rooms set status=$1",[status]);
      assert.equal((await call("DELETE","/me",a.token,confirmation)).status,409);
      assert.equal((await rows("nw_players")).length,2);assert.equal((await rows("nw_reports")).length,2);assert.equal((await rows("nw_rooms"))[0].a_name,"Old Identity");
    });
  }
  for(const status of ["registering","starting","running"]){
    it(`blocks ${status} tournament without awarding or cancelling`,async()=>{
      const {a}=await fixture();await pg.query("update nw_tournaments set status=$1",[status]);
      assert.equal((await call("DELETE","/me",a.token,confirmation)).status,409);
      assert.equal((await rows("nw_tournaments"))[0].status,status);assert.equal((await rows("nw_players")).length,2);
    });
  }
  it("fences an already authorized rematch commit after deletion",async()=>{
    const {a,b}=await fixture();
    await pg.query("update nw_rooms set state=$1::jsonb,b_rematch=true",[JSON.stringify(new Rules().serialize())]);
    const real=svc.db.transaction.bind(svc.db);let intercepted=false;
    svc.db.transaction=async steps=>{
      if(!intercepted && steps[0].text.startsWith("update nw_rooms")){
        intercepted=true;
        assert.equal((await call("DELETE","/me",a.token,confirmation)).status,200);
      }
      return real(steps);
    };
    const result=await call("POST","/rooms/ABCDE/rematch",a.token,{round:1});
    assert.ok(intercepted);assert.ok(result.status>=400);
    const room=(await rows("nw_rooms"))[0];
    assert.equal(room.status,"closed");assert.notEqual(room.rev,"rev");assert.equal(room.round,1);
    assert.equal(room.a_name,"####");assert.equal(room.a_player_id,null);assert.equal(room.a_rematch,false);assert.equal(room.b_rematch,false);
    assert.equal((await rows("nw_players"))[0].id,b.player_id);
  });
  it("cannot restore a deleted seat from a stale tournament envelope",async()=>{
    const {a}=await fixture();
    const stale=(await rows("nw_rooms"))[0] as RoomRow;
    assert.equal((await call("DELETE","/me",a.token,confirmation)).status,200);
    await assert.rejects(tournamentSeatToken(svc,stale,"a",a.token),/no longer available/);
    assert.equal((await rows("nw_rooms"))[0].a_token_hash,"deleted");
  });
  it("rechecks a cached seat token and rejects rotated sessions",async()=>{
    const {a}=await fixture();
    const room=(await rows("nw_rooms"))[0] as RoomRow;
    await tournamentSeatToken(svc,room,"a",a.token);
    await pg.query("update nw_players set token_hash=$1 where id=$2",[hashToken("nwd_rotated"),a.player_id]);
    await assert.rejects(tournamentSeatToken(svc,room,"a",a.token),/no longer available/);
  });
  it("rolls back all scrubbing when a later statement fails",async()=>{
    const {a}=await fixture();const real=svc.db.transaction.bind(svc.db);
    svc.db.transaction=(steps)=>real([...steps.slice(0,-2),{text:"select 1/0"},...steps.slice(-2)]);
    const old=console.error;console.error=()=>{};
    try{assert.equal((await call("DELETE","/me",a.token,confirmation)).status,500);}finally{console.error=old;}
    assert.equal((await rows("nw_players")).length,2);assert.equal((await rows("nw_rooms"))[0].a_name,"Old Identity");assert.equal((await rows("nw_reports")).length,2);
  });
  it("rechecks rotated credentials inside the locked transaction",async()=>{
    const {a}=await fixture();const real=svc.db.transaction.bind(svc.db);
    svc.db.transaction=async steps=>{await pg.query("update nw_players set token_hash=$1 where id=$2",[hashToken("nwd_new"),a.player_id]);return real(steps);};
    assert.equal((await call("DELETE","/me",a.token,confirmation)).status,401);
    assert.equal((await rows("nw_players")).length,2);assert.equal((await rows("nw_reports")).length,2);
  });
});

/** Isolated TEST deployment. Uses only Neon Functions' injected test database. */
import { neon, types } from '@neondatabase/serverless';
import { handleNineweaveRequest } from '../src/lib/nineweave/api.ts';
import { createService } from '../src/lib/nineweave/service.ts';
const url = process.env.DATABASE_URL;
if (!url || new URL(url).pathname !== '/lexerly_test') throw new Error('Isolated test database is not configured');
const overrides: Record<number, (v:string)=>unknown> = {20:Number,1082:(v)=>v,1186:(v)=>v};
const sql=neon(url,{types:{getTypeParser:((id:number,format?:'text'|'binary')=>overrides[id]??types.getTypeParser(id,format)) as never}});
const svc=createService({boardReadyEnabled:true,db:{query:async <T>(text:string,params:unknown[]=[]) => await sql.query(text,params) as T[], transaction:async (statements)=>await sql.transaction(statements.map(s=>sql.query(s.text,s.params??[]))) as Record<string,unknown>[][]}});
const origins=new Set(['https://elexerly.github.io','http://localhost:8060','http://127.0.0.1:8060']);
export default {async fetch(request:Request){
 const origin=request.headers.get('origin');
 if(origin&&!origins.has(origin)) return new Response('Test origin not allowed',{status:403});
 if(new URL(request.url).pathname==='/') return Response.json({application:'Lexerly isolated TEST API',production:false,email_enabled:false,board_ready_v1:true});
 const response=await handleNineweaveRequest(svc,request);
 response.headers.set('X-Lexerly-Environment','isolated-test');
 response.headers.set('Cache-Control','no-store');
 return response;
}};

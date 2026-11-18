import {rolldown} from 'rolldown';
const b=await rolldown({input:'test-host/index.ts',platform:'node',external:[/^node:/]});
await b.write({file:'test-host/dist/index.mjs',format:'esm'});await b.close();

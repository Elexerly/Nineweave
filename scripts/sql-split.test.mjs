import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { splitSqlStatements } from "./sql-split.mjs";
import { resolveDatabaseUrl, databaseUrlLooksMisconfigured } from "./database-url.mjs";

describe("splitSqlStatements", () => {
  it("splits on top-level semicolons and drops empties/comments", () => {
    assert.deepEqual(splitSqlStatements("create table a (x int);\n-- note; here\n;select 1;"), [
      "create table a (x int)",
      "select 1",
    ]);
  });
  it("keeps semicolons inside strings, identifiers, comments and dollar quotes", () => {
    const sql = `insert into t values ('a;b', 'it''s; ok');
create table "we;ird" (x int); /* block; comment */
create function f() returns int as $$ begin return 1; end; $$ language plpgsql;
select $tag$ ; $tag$;`;
    const parts = splitSqlStatements(sql);
    assert.equal(parts.length, 4);
    assert.match(parts[0], /'it''s; ok'/);
    assert.match(parts[1], /"we;ird"/);
    assert.match(parts[2], /return 1; end; \$\$ language plpgsql$/);
    assert.match(parts[3], /\$tag\$ ; \$tag\$$/);
  });
  it("returns nothing for a comment-only file", () => {
    assert.deepEqual(splitSqlStatements("-- just a comment\n/* and; this */\n"), []);
  });
});

describe("resolveDatabaseUrl", () => {
  const url = "postgresql://user:pw@ep-example.neon.tech/db?sslmode=require";
  const other = "postgres://other/x";
  it("prefers NINEWEAVE_DATABASE_URL when both are set", () => {
    assert.equal(
      resolveDatabaseUrl({
        DATABASE_URL: ` ${url} `,
        NINEWEAVE_DATABASE_URL: other,
      }),
      other,
    );
  });
  it("falls back to DATABASE_URL when NINEWEAVE_DATABASE_URL is unset", () => {
    assert.equal(resolveDatabaseUrl({ DATABASE_URL: ` ${url} ` }), url);
  });
  it("extracts the first URL from a pasted NINEWEAVE_DATABASE_URL block", () => {
    const block = `# Neon\nPGHOST=x\nDATABASE_URL='${url}'\nDATABASE_URL_UNPOOLED=postgres://second/db\n`;
    assert.equal(resolveDatabaseUrl({ NINEWEAVE_DATABASE_URL: block }), url);
  });
  it("prefers a pasted NINEWEAVE_DATABASE_URL block over DATABASE_URL", () => {
    const block = `# Neon\nDATABASE_URL='${url}'\n`;
    assert.equal(
      resolveDatabaseUrl({ DATABASE_URL: other, NINEWEAVE_DATABASE_URL: block }),
      url,
    );
  });
  it("extracts a postgres URL from a pasted DATABASE_URL block", () => {
    const block = `# wrapper\nDATABASE_URL="${url}"\n`;
    assert.equal(resolveDatabaseUrl({ DATABASE_URL: block }), url);
  });
  it("treats empty/whitespace as unset", () => {
    assert.equal(
      resolveDatabaseUrl({ DATABASE_URL: "  ", NINEWEAVE_DATABASE_URL: "\n" }),
      undefined,
    );
    assert.equal(resolveDatabaseUrl({}), undefined);
  });
  it("ignores a non-postgres value and flags it when nothing else is usable", () => {
    assert.equal(resolveDatabaseUrl({ DATABASE_URL: "mysql://x" }), undefined);
    assert.equal(databaseUrlLooksMisconfigured({ DATABASE_URL: "mysql://x" }), true);
    assert.equal(databaseUrlLooksMisconfigured({ NINEWEAVE_DATABASE_URL: "not-a-url" }), true);
    assert.equal(databaseUrlLooksMisconfigured({ DATABASE_URL: url }), false);
    assert.equal(
      databaseUrlLooksMisconfigured({
        NINEWEAVE_DATABASE_URL: "not-a-url",
        DATABASE_URL: url,
      }),
      false,
    );
  });
});

// @ts-check
/**
 * Split a migration file into single statements. The Neon HTTP driver runs one
 * statement per query (extended protocol), so `scripts/migrate.mjs` sends a
 * file as an array of statements inside one HTTP transaction.
 *
 * Understands `--` and nested block comments, single-quoted strings (incl.
 * E'' escapes), double-quoted identifiers and dollar-quoted bodies
 * (`$$ … $$`, `$tag$ … $tag$`), so semicolons inside those never split.
 * Empty / comment-only statements are dropped.
 *
 * @param {string} text
 * @returns {string[]}
 */
export function splitSqlStatements(text) {
  /** @type {string[]} */
  const out = [];
  let buf = "";
  let i = 0;
  const n = text.length;
  const push = () => {
    const stmt = buf.trim();
    if (stmt && stripComments(stmt).trim()) out.push(stmt);
    buf = "";
  };
  while (i < n) {
    const ch = text[i];
    const next = text[i + 1];
    if (ch === "-" && next === "-") {
      const end = text.indexOf("\n", i);
      const stop = end === -1 ? n : end + 1;
      buf += text.slice(i, stop);
      i = stop;
    } else if (ch === "/" && next === "*") {
      let depth = 1;
      let j = i + 2;
      while (j < n && depth > 0) {
        if (text[j] === "/" && text[j + 1] === "*") {
          depth += 1;
          j += 2;
        } else if (text[j] === "*" && text[j + 1] === "/") {
          depth -= 1;
          j += 2;
        } else j += 1;
      }
      buf += text.slice(i, j);
      i = j;
    } else if (ch === "'" || ch === '"') {
      const escapes = ch === "'" && /[eE]$/.test(buf) && !/\w[eE]$/.test(buf);
      let j = i + 1;
      while (j < n) {
        if (escapes && text[j] === "\\") {
          j += 2;
          continue;
        }
        if (text[j] === ch) {
          if (text[j + 1] === ch) {
            j += 2;
            continue;
          }
          break;
        }
        j += 1;
      }
      buf += text.slice(i, j + 1);
      i = j + 1;
    } else if (ch === "$") {
      const tag = text.slice(i).match(/^\$([A-Za-z_][A-Za-z0-9_]*)?\$/);
      if (tag && !/[A-Za-z0-9_]$/.test(buf)) {
        const close = text.indexOf(tag[0], i + tag[0].length);
        const stop = close === -1 ? n : close + tag[0].length;
        buf += text.slice(i, stop);
        i = stop;
      } else {
        buf += ch;
        i += 1;
      }
    } else if (ch === ";") {
      push();
      i += 1;
    } else {
      buf += ch;
      i += 1;
    }
  }
  push();
  return out;
}

/** @param {string} s */
function stripComments(s) {
  return s.replace(/--[^\n]*/g, "").replace(/\/\*[\s\S]*?\*\//g, "");
}

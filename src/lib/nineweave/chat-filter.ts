/**
 * In-match chat text rules: normalization, a basic English profanity mask
 * and hard blocks for slurs and contact info (URLs, emails, phone numbers,
 * messaging-app handles). The word lists live only here; keep them modest.
 *
 * Profanity is matched per word on a lowercased, accent-stripped,
 * leetspeak-folded form in which letters may repeat ("fuuuck") and `*` may
 * stand in for a letter ("f*ck", "sh*t"). Matches are masked with asterisks
 * of the same length and the message is still delivered.
 */
export const CHAT_MAX = 120;

export const CHAT_PRESETS: Readonly<Record<string, string>> = {
  gg: "Good game!",
  nice: "Nice move",
  rematch: "Rematch?",
  gl: "Good luck!",
  hi: "Hi!",
  thanks: "Thanks!",
  wow: "Wow!",
  oops: "Oops!",
};

// Masked when a word contains one of these.
const MASK_STEMS = [
  "fuck",
  "fuk",
  "shit",
  "bitch",
  "cunt",
  "pussy",
  "asshole",
  "arsehole",
  "bastard",
  "whore",
  "slut",
  "dildo",
  "jizz",
  "wank",
  "twat",
  "blowjob",
  "handjob",
  "motherf",
  "porn",
];
// Masked only as a whole word (substrings would hit "class", "Dickens", …).
const MASK_WORDS = [
  "ass",
  "asses",
  "arse",
  "damn",
  "dick",
  "dicks",
  "cock",
  "cocks",
  "cum",
  "tit",
  "tits",
  "boob",
  "boobs",
  "hoe",
  "hoes",
  "piss",
  "crap",
  "sex",
  "sexy",
  "horny",
  "stfu",
  "wtf",
  "fu",
];
// Hard-blocked (400): slurs and hate terms.
const BLOCK_STEMS = ["nigger", "nigga", "faggot", "kike", "tranny", "wetback", "raghead"];
const BLOCK_WORDS = ["fag", "fags", "spic", "chink", "gook", "coon", "retard", "retards", "kkk"];
const BLOCK_PHRASES = ["heil hitler", "kill yourself", "kys", "go die"];
// Squashed (spaces and punctuation removed) whole-message check for slurs
// spelled out letter by letter.
const BLOCK_SQUASHED = ["nigger", "nigga", "faggot"];

// Contact info and off-platform handles: never shareable in a 13+ game.
const URL_RE =
  /(?:https?:\/\/|www\.|\b[a-z0-9-]{2,}(?:\.|\s*(?:\(dot\)|\[dot\]|\sdot\s)\s*)(?:com|net|org|io|gg|me|co|tv|app|xyz|ly|be|us|uk|ru|info|biz|link|site|online|club|dev|chat|live|gay|sex|ws|to)\b)/i;
const EMAIL_RE =
  /[a-z0-9._%+-]+(?:@|\s*(?:\(at\)|\[at\])\s*)[a-z0-9-]+(?:\.|\s*(?:\(dot\)|\[dot\])\s*)[a-z]{2,}/i;
const PHONE_RE = /(?:\+?\d[\s().\-/]*){7,}/;
const HANDLE_WORDS = [
  "snapchat",
  "discord",
  "whatsapp",
  "telegram",
  "instagram",
  "insta",
  "tiktok",
  "kik",
  "facebook",
  "skype",
];

const LEET: Record<string, string> = {
  "0": "o",
  "1": "i",
  "3": "e",
  "4": "a",
  "5": "s",
  "7": "t",
  "8": "b",
  "@": "a",
  $: "s",
  "!": "i",
  "|": "i",
  "+": "t",
};

/** Strip control/format characters, turn newlines into spaces, collapse whitespace, trim. */
export function normalizeChatText(raw: string): string {
  return (
    raw
      .normalize("NFC")
      // Line breaks and tabs become spaces (single line).
      .replace(/[\r\n\t\v\f\u2028\u2029\u0085]/g, " ")
      // Other control, zero-width and bidi-override characters are dropped.
      // eslint-disable-next-line no-control-regex
      .replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]/g, "")
      .replace(/\s+/g, " ")
      .trim()
  );
}

/** Lowercase, strip accents, fold leetspeak; keeps `*` as a letter wildcard. */
function fold(word: string): string {
  const lower = word.toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "");
  return [...lower]
    .map((ch) => LEET[ch] ?? ch)
    .join("")
    .replace(/[^a-z*]/g, "");
}

const patternCache = new Map<string, RegExp>();
/** `fuck` -> f+[u*]+[c*]+[k*]+ (letters may repeat, `*` stands in for any but the first). */
function wordPattern(word: string, whole: boolean): RegExp {
  const key = `${whole ? "w" : "s"}:${word}`;
  let re = patternCache.get(key);
  if (!re) {
    const letters = [...word];
    const body = letters.map((l, i) => (i === 0 ? `${l}+` : `[${l}*]+`)).join("");
    re = new RegExp(whole ? `^${body}$` : body);
    patternCache.set(key, re);
  }
  return re;
}

function matches(folded: string, words: readonly string[], whole: boolean): boolean {
  if (!folded || folded.startsWith("*")) return false;
  const letters = folded.replace(/\*/g, "").length;
  return words.some(
    (w) =>
      letters >= Math.min(w.length, Math.max(2, Math.ceil(w.length / 2))) &&
      wordPattern(w, whole).test(folded),
  );
}

// A "word" is a run of non-space characters; leading/trailing ordinary
// punctuation is not part of it (so "shit!" and "(fuck)" still match).
const EDGE_PUNCT = /^[.,;:?!"'()[\]{}<>~_-]+|[.,;:?!"'()[\]{}<>~_-]+$/g;

function splitWord(token: string): { pre: string; core: string; post: string } {
  const lead = token.match(/^[.,;:?!"'()[\]{}<>~_-]+/)?.[0] ?? "";
  const rest = token.slice(lead.length);
  const trail = rest.match(/[.,;:?!"'()[\]{}<>~_-]+$/)?.[0] ?? "";
  return { pre: lead, core: rest.slice(0, rest.length - trail.length), post: trail };
}

export type ChatCheck =
  { ok: true; text: string; filtered: boolean } | { ok: false; error: string };

/** Is this text a hard block (slur, hate phrase, URL, email, phone, handle)? */
export function isBlockedChat(text: string): boolean {
  if (URL_RE.test(text) || EMAIL_RE.test(text) || PHONE_RE.test(text)) return true;
  const words = text.split(" ").map((t) => fold(t.replace(EDGE_PUNCT, "")));
  if (words.some((w) => HANDLE_WORDS.includes(w.replace(/\*/g, "")))) return true;
  if (words.some((w) => matches(w, BLOCK_STEMS, false) || matches(w, BLOCK_WORDS, true)))
    return true;
  const spaced = ` ${words.filter(Boolean).join(" ")} `;
  if (BLOCK_PHRASES.some((p) => spaced.includes(` ${p} `))) return true;
  const squashed = words.join("").replace(/\*/g, "");
  return BLOCK_SQUASHED.some((w) => squashed.includes(w));
}

/** Mask profanity word by word; returns the text and whether anything was masked. */
export function maskProfanity(text: string): { text: string; filtered: boolean } {
  let filtered = false;
  const out = text.split(" ").map((token) => {
    const { pre, core, post } = splitWord(token);
    const folded = fold(core);
    if (matches(folded, MASK_STEMS, false) || matches(folded, MASK_WORDS, true)) {
      filtered = true;
      return pre + "*".repeat([...core].length) + post;
    }
    return token;
  });
  return { text: out.join(" "), filtered };
}

/** Normalize, length-check, hard-block and mask a free-text chat message. */
export function checkChatText(raw: unknown): ChatCheck {
  if (typeof raw !== "string") return { ok: false, error: "text must be a string" };
  const text = normalizeChatText(raw);
  if (!text) return { ok: false, error: "Message can't be empty" };
  if ([...text].length > CHAT_MAX)
    return { ok: false, error: `Message must be ${CHAT_MAX} characters or fewer` };
  if (isBlockedChat(text)) return { ok: false, error: "Message not allowed" };
  return { ok: true, ...maskProfanity(text) };
}

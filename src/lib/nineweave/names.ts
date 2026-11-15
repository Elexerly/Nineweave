/**
 * Screen-name and display-name validation, including a basic English
 * profanity filter. Names are trimmed, whitespace-collapsed and capped at 24
 * characters (the protocol cap).
 */
export const NAME_MAX = 24;

// Letters (any script), digits, spaces and simple punctuation.
const ALLOWED = /^[\p{L}\p{N} .,'!?_\-()&+#:]+$/u;

// Matched against a normalized, separator-free, leetspeak-folded form, so
// "B.i.t.c.h" and "sh1t" are caught. Kept to unambiguous roots to limit false
// positives on ordinary names (no "ass", which would block "Cassandra").
const BLOCKED_SUBSTRINGS = [
  "fuck",
  "fuk",
  "fuq",
  "shit",
  "bitch",
  "cunt",
  "pussy",
  "asshole",
  "arsehole",
  "bastard",
  "whore",
  "slut",
  "nigger",
  "nigga",
  "faggot",
  "fagot",
  "retard",
  "molest",
  "paedo",
  "porn",
  "penis",
  "vagina",
  "dildo",
  "jizz",
  "cum shot",
  "cumshot",
  "wank",
  "twat",
  "boner",
  "blowjob",
  "handjob",
  "nazi",
  "hitler",
  "kike",
  "gook",
  "tranny",
  "motherf",
  "horny",
  "orgasm",
  "kkk",
];
// Whole-word only (would be false positives as substrings: "Scunthorpe" etc.).
const BLOCKED_WORDS = [
  "ass",
  "dick",
  "dicks",
  "cock",
  "cocks",
  "rapist",
  "pedo",
  "spic",
  "anal",
  "milf",
  "chink",
  "fag",
  "fags",
  "cum",
  "sex",
  "tit",
  "tits",
  "hoe",
  "hoes",
  "rape",
  "jap",
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
  "+": "t",
};

export function isProfane(name: string): boolean {
  const lower = name.toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "");
  const folded = [...lower].map((ch) => LEET[ch] ?? ch).join("");
  const squashed = folded.replace(/[^a-z]/g, "");
  if (BLOCKED_SUBSTRINGS.some((w) => squashed.includes(w.replace(/[^a-z]/g, "")))) return true;
  const words = folded.split(/[^a-z]+/).filter(Boolean);
  return words.some((w) => BLOCKED_WORDS.includes(w));
}

export type NameResult = { ok: true; name: string } | { ok: false; error: string };

/** Validate a screen name or in-room display name. */
export function validateName(raw: unknown, label = "Screen name"): NameResult {
  if (typeof raw !== "string") return { ok: false, error: `${label} must be text` };
  // Strip control characters, collapse whitespace, trim.
  // eslint-disable-next-line no-control-regex
  const name = raw
    .replace(/[\u0000-\u001f\u007f]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  if (!name) return { ok: false, error: `${label} can't be empty` };
  if ([...name].length > NAME_MAX)
    return { ok: false, error: `${label} must be ${NAME_MAX} characters or fewer` };
  if (!ALLOWED.test(name))
    return {
      ok: false,
      error: `${label} can only use letters, numbers, spaces and simple punctuation`,
    };
  if (isProfane(name))
    return { ok: false, error: `Please choose a different ${label.toLowerCase()}` };
  return { ok: true, name };
}

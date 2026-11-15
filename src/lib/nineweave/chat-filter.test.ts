/** Unit tests for the chat text rules (no database). */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  CHAT_MAX,
  CHAT_PRESETS,
  checkChatText,
  isBlockedChat,
  maskProfanity,
  normalizeChatText,
} from "./chat-filter.ts";

const ok = (raw: string) => {
  const res = checkChatText(raw);
  assert.ok(res.ok, `expected ${JSON.stringify(raw)} to pass`);
  return res;
};

describe("chat filter", () => {
  it("normalizes to a single trimmed line without control characters", () => {
    assert.equal(normalizeChatText("  hi\nthere\r\n\tfriend  "), "hi there friend");
    assert.equal(normalizeChatText("a\u0000b\u0007c​d‮e"), "abcde");
    assert.equal(normalizeChatText("so    many   spaces"), "so many spaces");
  });

  it("enforces non-empty and the 120-character cap after trimming", () => {
    assert.deepEqual(checkChatText("   \n\t "), { ok: false, error: "Message can't be empty" });
    assert.equal(checkChatText(42).ok, false);
    assert.equal(ok(`  ${"a".repeat(CHAT_MAX)}  `).text.length, CHAT_MAX);
    const long = checkChatText("a".repeat(CHAT_MAX + 1));
    assert.equal(long.ok, false);
  });

  it("masks profanity with same-length asterisks, including leetspeak and obfuscation", () => {
    const cases: [string, string][] = [
      ["what the fuck", "what the ****"],
      ["what the f*ck", "what the ****"],
      ["f**k this", "**** this"],
      ["sh1t happens", "**** happens"],
      ["you a$$!", "you ***!"],
      ["FUUUCK", "******"],
      ["(shit)", "(****)"],
      ["sh!t move", "**** move"],
      ["motherfucker", "************"],
      ["Bítch please", "***** please"],
    ];
    for (const [input, expected] of cases) {
      const res = ok(input);
      assert.equal(res.text, expected, input);
      assert.equal(res.filtered, true, input);
    }
  });

  it("leaves ordinary words alone", () => {
    for (const clean of [
      "Good game, well played!",
      "nice move on board 4",
      "that was a classic assassin play",
      "I pass, as usual",
      "Dickens fan here",
      "cocktail party",
      "3 boards to go",
      "gg wp",
      "Oh snap!",
      "see you at the next match",
    ]) {
      const res = ok(clean);
      assert.equal(res.text, clean);
      assert.equal(res.filtered, false, clean);
    }
    assert.deepEqual(maskProfanity("hello"), { text: "hello", filtered: false });
  });

  it("hard-blocks slurs and hate phrases", () => {
    for (const bad of ["you n1gger", "f a g g o t", "dirty kike", "heil hitler", "kys"]) {
      assert.deepEqual(checkChatText(bad), { ok: false, error: "Message not allowed" }, bad);
    }
  });

  it("hard-blocks URLs, email addresses, phone numbers and messaging handles", () => {
    for (const bad of [
      "go to https://example.org",
      "www.example.com",
      "join discord.gg/abc123",
      "my site example.com",
      "example dot com",
      "mail me: kid@example.com",
      "kid (at) example (dot) com",
      "call 555-123-4567",
      "+1 (555) 123 4567",
      "text me 5551234567",
      "add me on snapchat",
      "my discord is xyz",
    ]) {
      assert.equal(isBlockedChat(normalizeChatText(bad)), true, bad);
      assert.deepEqual(checkChatText(bad), { ok: false, error: "Message not allowed" }, bad);
    }
  });

  it("exposes the quick-chat presets", () => {
    assert.deepEqual(CHAT_PRESETS, {
      gg: "Good game!",
      nice: "Nice move",
      rematch: "Rematch?",
      gl: "Good luck!",
      hi: "Hi!",
      thanks: "Thanks!",
      wow: "Wow!",
      oops: "Oops!",
    });
  });
});

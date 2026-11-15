import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { DRAW, MASKS, LINES, O, OPEN, Rules, X } from "./rules.ts";
import { DRAW_GAME_X_MORE_BOARDS, X_WIN_GAME } from "./fixtures.ts";

function playAll(moves: [number, number][]) {
  const r = new Rules();
  for (const [b, c] of moves) assert.ok(r.play(b, c), `move ${b},${c} should be legal`);
  return r;
}

describe("rules kernel (parity with rules.gd)", () => {
  it("masks match the line definitions", () => {
    LINES.forEach((line, i) =>
      assert.equal(
        line.reduce((m, c) => m | (1 << c), 0),
        MASKS[i],
      ),
    );
  });

  it("starts empty with X to move anywhere", () => {
    const r = new Rules();
    assert.equal(r.turn, X);
    assert.equal(r.activeBoard, -1);
    assert.equal(r.legalMoves().length, 81);
    assert.deepEqual(r.serialize(), {
      v: 1,
      cells: ".".repeat(81),
      turn: 1,
      active: -1,
      history: [],
      redo: [],
    });
  });

  it("rejects out-of-range, occupied and wrong-board moves", () => {
    const r = new Rules();
    for (const [b, c] of [
      [-1, 0],
      [9, 0],
      [0, 9],
      [0, -1],
      [1.5, 0],
    ] as [number, number][])
      assert.equal(r.isLegal(b, c), false);
    assert.ok(r.play(4, 0)); // sends O to board 0
    assert.equal(r.activeBoard, 0);
    assert.equal(r.isLegal(4, 1), false, "must play in board 0");
    assert.equal(r.play(4, 1), false);
    assert.equal(r.lastError, "Choose an empty cell in the active board");
    assert.ok(r.play(0, 4)); // sends X back to board 4
    assert.equal(r.isLegal(4, 0), false, "occupied");
    assert.ok(r.isLegal(4, 1));
  });

  it("sends the opponent to the board matching the cell", () => {
    const r = new Rules();
    r.play(0, 5);
    assert.equal(r.activeBoard, 5);
    assert.equal(r.turn, O);
    assert.deepEqual(r.history[0], { board: 0, cell: 5, player: X, active_before: -1 });
  });

  it("claims a small board on three in a row and grants a free move when sent there", () => {
    // X takes board 0 with cells 0,1,2; O's replies on cell 0 bounce X back to board 0.
    const r = playAll([
      [0, 0],
      [0, 3],
      [3, 4],
      [4, 0],
      [0, 1],
      [1, 0],
    ]);
    assert.equal(r.activeBoard, 0);
    assert.ok(r.play(0, 2));
    assert.equal(r.owners[0], X);
    assert.deepEqual(r.smallLines[0], [[0, 1, 2]]);
    // O is sent to board 2 (open) — normal.
    assert.equal(r.activeBoard, 2);
    assert.ok(r.play(2, 0)); // sends X to board 0, which is claimed -> free move
    assert.equal(r.activeBoard, -1);
    assert.equal(r.isLegal(0, 6), false, "claimed board is closed");
    assert.ok(r.isLegal(8, 8));
  });

  it("marks a full board with no line as drawn and frees the next move", () => {
    // Fill board 4 to a draw: X O X / X O O / O X X
    const pattern = [X, O, X, X, O, O, O, X, X];
    const r = new Rules();
    // Build directly through deserialize so the draw arises from the cells.
    const cells = Array(81).fill(".");
    pattern.forEach((m, i) => (cells[36 + i] = m === X ? "X" : "O"));
    const restored = Rules.deserialize({
      v: 1,
      cells: cells.join(""),
      turn: X,
      active: -1,
      history: [],
      redo: [],
    });
    assert.ok(restored);
    assert.equal(restored!.owners[4], DRAW);
    assert.equal(restored!.isLegal(0, 4), true);
    restored!.play(0, 4); // target board 4 is drawn -> free move
    assert.equal(restored!.activeBoard, -1);
    assert.equal(r.owners[4], OPEN);
  });

  it("wins the match with three claimed boards in a line", () => {
    const r = playAll(X_WIN_GAME);
    assert.equal(r.status, X);
    assert.equal(r.winner(), X);
    assert.ok(r.bigLines.length >= 1);
    assert.equal(r.play(0, 0), false);
    assert.equal(r.lastError, "Game finished");
    assert.deepEqual(r.legalMoves(), []);
  });

  it("is a draw when no boards remain open — no board-count tiebreak", () => {
    const r = playAll(DRAW_GAME_X_MORE_BOARDS);
    assert.equal(r.status, DRAW);
    assert.equal(r.winner(), OPEN);
    assert.equal(r.boardsWon(X), 5);
    assert.equal(r.boardsWon(O), 4);
  });

  it("serializes to 81 chars and round-trips through deserialize", () => {
    const r = playAll(X_WIN_GAME.slice(0, 10));
    const s = r.serialize();
    assert.equal(s.cells.length, 81);
    assert.match(s.cells, /^[.XO]{81}$/);
    assert.equal(s.history.length, 10);
    const back = Rules.deserialize(JSON.stringify(s));
    assert.ok(back);
    assert.deepEqual(back!.serialize(), s);
    assert.deepEqual(back!.owners, r.owners);
  });

  it("rejects inconsistent snapshots", () => {
    const s = playAll(X_WIN_GAME.slice(0, 4)).serialize();
    assert.equal(Rules.deserialize({ ...s, cells: s.cells.slice(1) }), null);
    assert.equal(Rules.deserialize({ ...s, cells: "Z" + s.cells.slice(1) }), null);
    assert.equal(Rules.deserialize({ ...s, v: 2 }), null);
    assert.equal(Rules.deserialize({ ...s, turn: 3 }), null);
    assert.equal(Rules.deserialize({ ...s, turn: 2 }), null, "history replay disagrees with turn");
    assert.equal(Rules.deserialize({ ...s, history: s.history.slice(1) }), null);
    assert.equal(Rules.deserialize("not json"), null);
  });

  it("fromHistory replays authoritatively", () => {
    const r = Rules.fromHistory(X_WIN_GAME.map(([board, cell]) => ({ board, cell })));
    assert.equal(r.status, X);
    assert.throws(() =>
      Rules.fromHistory([
        { board: 0, cell: 0 },
        { board: 0, cell: 0 },
      ]),
    );
  });
});

/**
 * Ultimate Tic Tac Toe rules kernel — a 1:1 port of the Godot client's
 * `godot/kernel/rules.gd`. Pure and deterministic: no HTTP, DB, clock or I/O.
 *
 * Marks/status: OPEN=0, X=1, O=2, DRAW=3. `activeBoard = -1` means "any open
 * board". A move on cell C sends the opponent to board C unless that board is
 * already claimed (won or drawn/full), in which case they get a free move.
 * There is no board-count tiebreak: a game with no big line is a draw.
 */

export const OPEN = 0;
export const X = 1;
export const O = 2;
export const DRAW = 3;

export type Player = typeof X | typeof O;

export const LINES: readonly (readonly [number, number, number])[] = [
  [0, 1, 2],
  [3, 4, 5],
  [6, 7, 8],
  [0, 3, 6],
  [1, 4, 7],
  [2, 5, 8],
  [0, 4, 8],
  [2, 4, 6],
];
export const MASKS: readonly number[] = [7, 56, 448, 73, 146, 292, 273, 84];

export interface HistoryEntry {
  board: number;
  cell: number;
  player: number;
  active_before: number;
}

/** Wire snapshot, identical to `rules.gd` `serialize()`. */
export interface SerializedState {
  v: 1;
  cells: string;
  turn: number;
  active: number;
  history: HistoryEntry[];
  redo: HistoryEntry[];
}

export function hasLine(mask: number): boolean {
  for (const m of MASKS) if ((mask & m) === m) return true;
  return false;
}

export function linesForMask(mask: number): number[][] {
  const result: number[][] = [];
  for (let i = 0; i < 8; i += 1) if ((mask & MASKS[i]) === MASKS[i]) result.push([...LINES[i]]);
  return result;
}

export class Rules {
  cells: number[] = [];
  owners: number[] = [];
  xMasks: number[] = [];
  oMasks: number[] = [];
  counts: number[] = [];
  turn: number = X;
  activeBoard = -1;
  status = OPEN;
  history: HistoryEntry[] = [];
  redoStack: HistoryEntry[] = [];
  smallLines: number[][][] = [];
  bigLines: number[][] = [];
  lastError = "";

  constructor() {
    this.newGame();
  }

  newGame(): void {
    this.cells = new Array(81).fill(OPEN);
    this.owners = new Array(9).fill(OPEN);
    this.xMasks = new Array(9).fill(0);
    this.oMasks = new Array(9).fill(0);
    this.counts = new Array(9).fill(0);
    this.smallLines = Array.from({ length: 9 }, () => []);
    this.bigLines = [];
    this.history = [];
    this.redoStack = [];
    this.turn = X;
    this.activeBoard = -1;
    this.status = OPEN;
    this.lastError = "";
  }

  /** X or O when someone won the match, else OPEN (also for a draw). */
  winner(): number {
    return this.status === X || this.status === O ? this.status : OPEN;
  }

  boardOwner(board: number): number {
    return board >= 0 && board < 9 ? this.owners[board] : -1;
  }

  isLegal(board: number, cell: number): boolean {
    return (
      this.status === OPEN &&
      Number.isInteger(board) &&
      Number.isInteger(cell) &&
      board >= 0 &&
      board < 9 &&
      cell >= 0 &&
      cell < 9 &&
      this.owners[board] === OPEN &&
      (this.activeBoard === -1 || board === this.activeBoard) &&
      this.cells[board * 9 + cell] === OPEN
    );
  }

  legalMoves(): [number, number][] {
    const result: [number, number][] = [];
    if (this.status !== OPEN) return result;
    for (let b = 0; b < 9; b += 1) {
      if (this.owners[b] !== OPEN || (this.activeBoard !== -1 && b !== this.activeBoard)) continue;
      for (let c = 0; c < 9; c += 1) if (this.cells[b * 9 + c] === OPEN) result.push([b, c]);
    }
    return result;
  }

  play(board: number, cell: number): boolean {
    if (!this.isLegal(board, cell)) {
      this.lastError =
        this.status !== OPEN ? "Game finished" : "Choose an empty cell in the active board";
      return false;
    }
    this.history.push({ board, cell, player: this.turn, active_before: this.activeBoard });
    this.redoStack = [];
    this.cells[board * 9 + cell] = this.turn;
    this.counts[board] += 1;
    if (this.turn === X) this.xMasks[board] |= 1 << cell;
    else this.oMasks[board] |= 1 << cell;
    const mask = this.turn === X ? this.xMasks[board] : this.oMasks[board];
    if (hasLine(mask)) {
      this.owners[board] = this.turn;
      this.smallLines[board] = linesForMask(mask);
      this.updateStatus();
    } else if (this.counts[board] === 9) {
      this.owners[board] = DRAW;
      this.updateStatus();
    }
    this.activeBoard = this.owners[cell] === OPEN ? cell : -1;
    this.turn = 3 - this.turn;
    this.lastError = "";
    return true;
  }

  private updateStatus(): void {
    this.status = OPEN;
    this.bigLines = [];
    for (const p of [X, O]) {
      let mask = 0;
      for (let b = 0; b < 9; b += 1) if (this.owners[b] === p) mask |= 1 << b;
      const found = linesForMask(mask);
      if (found.length > 0) {
        this.status = p;
        this.bigLines = found;
        return;
      }
    }
    if (!this.owners.includes(OPEN)) this.status = DRAW;
  }

  /** Small boards claimed (won, not drawn) by `player`. */
  boardsWon(player: number): number {
    return this.owners.filter((o) => o === player).length;
  }

  serialize(): SerializedState {
    return {
      v: 1,
      cells: this.cells.map((m) => ".XO"[m]).join(""),
      turn: this.turn,
      active: this.activeBoard,
      history: this.history.map((m) => ({ ...m })),
      redo: this.redoStack.map((m) => ({ ...m })),
    };
  }

  /** Rebuild authoritatively by replaying a move list. */
  static fromHistory(history: readonly { board: number; cell: number }[]): Rules {
    const r = new Rules();
    for (const m of history) {
      if (!r.play(m.board, m.cell)) throw new Error("Inconsistent move history");
    }
    return r;
  }

  /**
   * Transactional restore, mirroring `rules.gd` `deserialize()`: recomputes
   * owners/lines and rejects inconsistent histories. Returns null on failure.
   */
  static deserialize(input: unknown): Rules | null {
    let data = input;
    if (typeof data === "string") {
      try {
        data = JSON.parse(data);
      } catch {
        return null;
      }
    }
    if (!data || typeof data !== "object" || Array.isArray(data)) return null;
    const d = data as Record<string, unknown>;
    if (d.v !== 1) return null;
    const text = d.cells;
    if (typeof text !== "string" || text.length !== 81) return null;
    const p = d.turn;
    const a = d.active;
    if (typeof p !== "number" || typeof a !== "number") return null;
    if (!Number.isInteger(p) || !Number.isInteger(a)) return null;
    if ((p !== X && p !== O) || a < -1 || a > 8) return null;

    const r = new Rules();
    for (let i = 0; i < 81; i += 1) {
      const mark = ".XO".indexOf(text[i]);
      if (mark < 0) return null;
      r.cells[i] = mark;
      const b = Math.floor(i / 9);
      const c = i % 9;
      if (mark !== OPEN) r.counts[b] += 1;
      if (mark === X) r.xMasks[b] |= 1 << c;
      else if (mark === O) r.oMasks[b] |= 1 << c;
    }
    for (let b = 0; b < 9; b += 1) {
      if (hasLine(r.xMasks[b]) && hasLine(r.oMasks[b])) return null;
      for (const mark of [X, O]) {
        const mask = mark === X ? r.xMasks[b] : r.oMasks[b];
        if (hasLine(mask)) {
          r.owners[b] = mark;
          r.smallLines[b] = linesForMask(mask);
        }
      }
      if (r.owners[b] === OPEN && r.counts[b] === 9) r.owners[b] = DRAW;
    }
    r.updateStatus();
    if (a !== -1 && r.owners[a] !== OPEN) return null;
    r.turn = p;
    r.activeBoard = a;

    const h = d.history ?? [];
    if (!Array.isArray(h)) return null;
    if (h.length > 0) {
      const replay = new Rules();
      for (const m of h) {
        if (!isEntry(m)) return null;
        if (replay.turn !== m.player || replay.activeBoard !== m.active_before) return null;
        if (!replay.play(m.board, m.cell)) return null;
      }
      if (replay.cells.join() !== r.cells.join() || replay.turn !== p || replay.activeBoard !== a)
        return null;
      r.history = replay.history;
    }

    const pending = d.redo ?? [];
    if (!Array.isArray(pending)) return null;
    const check = r.copy();
    for (let j = pending.length - 1; j >= 0; j -= 1) {
      const m = pending[j];
      if (!isEntry(m)) return null;
      if (check.turn !== m.player || check.activeBoard !== m.active_before) return null;
      if (!check.play(m.board, m.cell)) return null;
    }
    r.redoStack = pending.map((m: HistoryEntry) => ({
      board: m.board,
      cell: m.cell,
      player: m.player,
      active_before: m.active_before,
    }));
    return r;
  }

  copy(): Rules {
    const r = new Rules();
    r.cells = [...this.cells];
    r.owners = [...this.owners];
    r.xMasks = [...this.xMasks];
    r.oMasks = [...this.oMasks];
    r.counts = [...this.counts];
    r.turn = this.turn;
    r.activeBoard = this.activeBoard;
    r.status = this.status;
    r.smallLines = this.smallLines.map((l) => l.map((x) => [...x]));
    r.bigLines = this.bigLines.map((x) => [...x]);
    r.history = this.history.map((m) => ({ ...m }));
    r.redoStack = this.redoStack.map((m) => ({ ...m }));
    return r;
  }
}

function isEntry(m: unknown): m is HistoryEntry {
  if (!m || typeof m !== "object") return false;
  const e = m as Record<string, unknown>;
  return ["board", "cell", "player", "active_before"].every(
    (k) => typeof e[k] === "number" && Number.isInteger(e[k]),
  );
}

class_name NineweaveRules
extends RefCounted
## Pure deterministic rules. No Nodes, signals, clock, filesystem or UI dependencies.
## Marks/status: OPEN=0, X=1, O=2, DRAW=3. active_board=-1 means any.
const OPEN = 0
const X = 1
const O = 2
const DRAW = 3
const LINES = [[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]]
const MASKS = [7,56,448,73,146,292,273,84]
const BOARD_NAMES = ["Top Left","Top","Top Right","Left","Center","Right","Bottom Left","Bottom","Bottom Right"]
var cells = PackedInt32Array()
var owners = PackedInt32Array()
var x_masks = PackedInt32Array()
var o_masks = PackedInt32Array()
var counts = PackedInt32Array()
var turn: int = X
var active_board: int = -1
var status: int = OPEN
var history: Array = []
var redo_stack: Array = []
var small_lines: Array = []
var big_lines: Array = []
var last_error: String = ""

func _init(): new_game()

func new_game() -> void:
	cells.resize(81); cells.fill(0)
	owners.resize(9); owners.fill(0)
	x_masks.resize(9); x_masks.fill(0)
	o_masks.resize(9); o_masks.fill(0)
	counts.resize(9); counts.fill(0)
	small_lines = [[],[],[],[],[],[],[],[],[]]
	big_lines = []; history = []; redo_stack = []
	turn = X; active_board = -1; status = OPEN; last_error = ""

func winner() -> int: return status if status in [X,O] else OPEN
func move_history() -> Array: return history.duplicate(true)
func board_owner(board: int) -> int: return owners[board] if board >= 0 and board < 9 else -1
func winning_lines(board: int = -1) -> Array:
	return big_lines.duplicate(true) if board == -1 else small_lines[board].duplicate(true)
func is_legal(board: int, cell: int) -> bool:
	return status == OPEN and board >= 0 and board < 9 and cell >= 0 and cell < 9 and owners[board] == OPEN and (active_board == -1 or board == active_board) and cells[board*9+cell] == OPEN
func legal_moves() -> Array:
	var result: Array = []
	if status != OPEN: return result
	for b in range(9):
		if owners[b] != OPEN or (active_board != -1 and b != active_board): continue
		for c in range(9):
			if cells[b*9+c] == OPEN: result.append(Vector2i(b,c))
	return result

static func lines_for_mask(mask: int) -> Array:
	var result: Array = []
	for i in range(8):
		if mask & MASKS[i] == MASKS[i]: result.append(LINES[i].duplicate())
	return result
static func has_line(mask: int) -> bool:
	for m in MASKS:
		if mask & m == m: return true
	return false
func would_claim(board: int, cell: int, player: int) -> bool:
	if owners[board] != OPEN or cells[board*9+cell] != OPEN: return false
	return has_line((x_masks[board] if player == X else o_masks[board]) | (1 << cell))
func would_win_game(board: int, cell: int, player: int) -> bool:
	if not would_claim(board,cell,player): return false
	var mask = 1 << board
	for b in range(9):
		if owners[b] == player: mask |= 1 << b
	return has_line(mask)

func play(board: int, cell: int) -> bool:
	if not is_legal(board,cell):
		last_error = "Game finished" if status != OPEN else "Choose an empty cell in the active board"
		return false
	history.append({"board":board,"cell":cell,"player":turn,"active_before":active_board})
	redo_stack.clear()
	cells[board*9+cell] = turn
	counts[board] += 1
	if turn == X: x_masks[board] |= 1 << cell
	else: o_masks[board] |= 1 << cell
	var mask: int = x_masks[board] if turn == X else o_masks[board]
	if has_line(mask):
		owners[board] = turn
		small_lines[board] = lines_for_mask(mask)
		_update_status()
	elif counts[board] == 9:
		owners[board] = DRAW
		_update_status()
	active_board = cell if owners[cell] == OPEN else -1
	turn = 3-turn
	last_error = ""
	return true

func _update_status() -> void:
	status = OPEN; big_lines = []
	for p in [X,O]:
		var mask = 0
		for b in range(9):
			if owners[b] == p: mask |= 1 << b
		var found = lines_for_mask(mask)
		if not found.is_empty():
			status = p; big_lines = found
			return
	if not owners.has(OPEN): status = DRAW

func undo() -> bool:
	if history.is_empty(): return false
	var m: Dictionary = history.pop_back()
	var b: int = m.board; var c: int = m.cell
	cells[b*9+c] = OPEN; counts[b] -= 1
	if m.player == X: x_masks[b] &= ~(1 << c)
	else: o_masks[b] &= ~(1 << c)
	owners[b] = OPEN; small_lines[b] = []
	turn = m.player; active_board = m.active_before
	_update_status()
	redo_stack.append(m)
	return true
func redo() -> bool:
	if redo_stack.is_empty(): return false
	var pending = redo_stack.duplicate(true)
	var m: Dictionary = pending.pop_back()
	if not play(m.board,m.cell): return false
	redo_stack = pending
	return true
func copy(include_history: bool = true):
	var r = get_script().new()
	r.cells = cells.duplicate(); r.owners = owners.duplicate()
	r.x_masks = x_masks.duplicate(); r.o_masks = o_masks.duplicate(); r.counts = counts.duplicate()
	r.turn = turn; r.active_board = active_board; r.status = status
	r.small_lines = small_lines.duplicate(true); r.big_lines = big_lines.duplicate(true)
	if include_history:
		r.history = history.duplicate(true); r.redo_stack = redo_stack.duplicate(true)
	return r

func serialize() -> Dictionary:
	var text = ""
	for mark in cells: text += ".XO"[mark]
	return {"v":1,"cells":text,"turn":turn,"active":active_board,"history":history.duplicate(true),"redo":redo_stack.duplicate(true)}
func compact() -> String: return JSON.stringify(serialize())
## Transactional restore. Recomputes owners/lines; rejects inconsistent histories.
func deserialize(data) -> bool:
	if data is String:
		var parser = JSON.new()
		if parser.parse(data) != OK: return false
		data = parser.data
	if not data is Dictionary or data.get("v",0) != 1: return false
	var text = data.get("cells","")
	if not text is String or text.length() != 81: return false
	var raw_p = data.get("turn",0); var raw_a = data.get("active",-2)
	if not (raw_p is int or raw_p is float) or not (raw_a is int or raw_a is float): return false
	var p = int(raw_p); var a = int(raw_a)
	if p != raw_p or a != raw_a: return false
	if not p in [X,O] or a < -1 or a > 8: return false
	var r = get_script().new()
	for i in range(81):
		var mark = ".XO".find(text[i])
		if mark < 0: return false
		r.cells[i] = mark
		var b = i/9; var c = i%9
		if mark != OPEN: r.counts[b] += 1
		if mark == X: r.x_masks[b] |= 1 << c
		elif mark == O: r.o_masks[b] |= 1 << c
	for b in range(9):
		if has_line(r.x_masks[b]) and has_line(r.o_masks[b]): return false
		for mark in [X,O]:
			var mask = r.x_masks[b] if mark == X else r.o_masks[b]
			if has_line(mask): r.owners[b] = mark; r.small_lines[b] = lines_for_mask(mask)
		if r.owners[b] == OPEN and r.counts[b] == 9: r.owners[b] = DRAW
	r._update_status()
	if a != -1 and r.owners[a] != OPEN: return false
	r.turn = p; r.active_board = a
	var h = data.get("history",[])
	if not h is Array: return false
	if not h.is_empty():
		var replay = get_script().new()
		for m in h:
			if not m is Dictionary or not m.has_all(["board","cell","player","active_before"]): return false
			if replay.turn != m.player or replay.active_board != m.active_before or not replay.play(int(m.board),int(m.cell)): return false
		if replay.cells != r.cells or replay.turn != p or replay.active_board != a: return false
		r.history = replay.history
	var pending = data.get("redo",[])
	if not pending is Array: return false
	var check = r.copy()
	for j in range(pending.size()-1,-1,-1):
		var m = pending[j]
		if not m is Dictionary or not m.has_all(["board","cell","player","active_before"]): return false
		if check.turn != m.player or check.active_board != m.active_before or not check.play(int(m.board),int(m.cell)): return false
	cells = r.cells; owners = r.owners; x_masks = r.x_masks; o_masks = r.o_masks; counts = r.counts
	turn = r.turn; active_board = r.active_board; status = r.status
	small_lines = r.small_lines; big_lines = r.big_lines; history = r.history; redo_stack = []
	for m in pending: redo_stack.append({"board":int(m.board),"cell":int(m.cell),"player":int(m.player),"active_before":int(m.active_before)})
	return true

class_name NineweaveAI
extends RefCounted
## Seeded heuristic + incremental, beam-ordered alpha-beta. No threads.
const Rules = preload("res://kernel/rules.gd")
var rng = RandomNumberGenerator.new()
var difficulty: String = "Hard"
var budget_ms: int = 450
var node_limit: int = 700
var nodes: int = 0
var elapsed_ms: float = 0
var best_move = Vector2i(-1,-1)
var done: bool = true
var _game
var _moves: Array = []
var _cursor: int = 0
var _depth: int = 0
var _best_score: float = -INF
var _round_best = Vector2i(-1,-1)
var _deadline: int = 0
var _started: int = 0
var _player: int = 1
var _stack: Array = []
var max_slice_ms: float = 0

func _init(seed_value: int = 1): rng.seed = seed_value
func begin(game, level: String = "Hard", seed_value: int = -1) -> void:
	if seed_value >= 0: rng.seed = seed_value
	difficulty = level; nodes = 0; done = false; elapsed_ms = 0
	_stack = []; max_slice_ms = 0
	_game = game.copy(false); _player = game.turn
	_started = Time.get_ticks_usec(); _deadline = _started + budget_ms*1000
	_moves = ordered(_game,_game.legal_moves())
	if _moves.is_empty(): best_move = Vector2i(-1,-1); done = true; return
	best_move = _moves[0]
	if level == "Easy":
		best_move = _moves[rng.randi_range(0,_moves.size()-1)]
		if rng.randf() < .12 and _game.would_claim(_moves[0].x,_moves[0].y,_player): best_move = _moves[0]
		done = true; return
	if level == "Medium":
		# Small seeded noise, always subordinate to a tactical win or block.
		var score = -INF
		for m in _moves:
			var value = move_score(_game,m) + rng.randf()*3.0
			if value > score: score = value; best_move = m
		done = true; return
	# Immediate terminal moves precede every search/time cutoff.
	for m in _moves:
		if _game.would_win_game(m.x,m.y,_player): best_move = m; done = true; return
	_moves = _moves.slice(0,mini(18,_moves.size()))
	_cursor = 0; _depth = 2; _best_score = -INF; _round_best = best_move

func _frame(depth: int, alpha: float, beta: float) -> Dictionary:
	return {"depth":depth,"alpha":alpha,"beta":beta,"best":-INF,"entered":false,"moves":[],"cursor":0}
func step(slice_us: int = 5000) -> bool:
	if done: return true
	var slice_start = Time.get_ticks_usec()
	var slice_end = slice_start + slice_us
	while Time.get_ticks_usec() < slice_end and not done:
		if nodes >= node_limit or Time.get_ticks_usec() >= _deadline:
			done = true; _stack.clear(); break
		if _stack.is_empty():
			var root_move: Vector2i = _moves[_cursor]
			_game.play(root_move.x,root_move.y)
			_stack.append(_frame(_depth-1,-INF,INF))
		var f: Dictionary = _stack.back()
		if not f.entered:
			nodes += 1; f.entered = true
			if _game.status != 0:
				var value = 0.0
				if _game.status != Rules.DRAW: value = (1000000.0+f.depth*1000)*(1 if _game.status == _game.turn else -1)
				_finish_frame(value); continue
			if f.depth == 0:
				_finish_frame(evaluate(_game,_game.turn)); continue
			f.moves = ordered(_game,_game.legal_moves())
			f.moves = f.moves.slice(0,mini(7,f.moves.size()))
		if f.cursor >= f.moves.size() or f.alpha >= f.beta:
			_finish_frame(f.best); continue
		var m: Vector2i = f.moves[f.cursor]
		_game.play(m.x,m.y)
		_stack.append(_frame(f.depth-1,-f.beta,-f.alpha))
	elapsed_ms = (Time.get_ticks_usec()-_started)/1000.0
	max_slice_ms = maxf(max_slice_ms,(Time.get_ticks_usec()-slice_start)/1000.0)
	return done
func _finish_frame(value: float):
	_stack.pop_back()
	_game.undo()
	if not _stack.is_empty():
		var parent: Dictionary = _stack.back()
		parent.best = maxf(parent.best,-value)
		parent.alpha = maxf(parent.alpha,parent.best)
		parent.cursor += 1
		return
	var score = -value
	if score > _best_score: _best_score = score; _round_best = _moves[_cursor]
	_cursor += 1
	if _cursor == _moves.size():
		best_move = _round_best
		if _depth >= 4: done = true
		else: _depth += 1; _cursor = 0; _best_score = -INF
func choose_move(game, level: String = "Hard", seed_value: int = -1) -> Vector2i:
	begin(game,level,seed_value)
	while not done: step(8000)
	elapsed_ms = (Time.get_ticks_usec()-_started)/1000.0
	return best_move

func ordered(g, moves: Array) -> Array:
	var weighted: Array = []
	for m in moves: weighted.append([m,move_score(g,m)])
	weighted.sort_custom(func(a,b): return a[1] > b[1])
	var result: Array = []
	for pair in weighted: result.append(pair[0])
	return result
func move_score(g, m: Vector2i) -> float:
	var b = m.x; var c = m.y; var p = g.turn; var enemy = 3-p
	var score = 0.0
	if g.would_win_game(b,c,p): return 1000000.0
	if g.would_win_game(b,c,enemy): score += 220000
	var importance = board_value(g,b,p)
	if g.would_claim(b,c,p): score += 2000 + importance*30
	if g.would_claim(b,c,enemy): score += 1200 + board_value(g,b,enemy)*26
	# Evaluate routing AFTER this cell is occupied, including closing our own target.
	var target_closed: bool = g.owners[c] != 0 or (b == c and (g.would_claim(b,c,p) or g.counts[b] == 8))
	if target_closed: score -= 260
	else:
		for k in range(9):
			if c == b and k == m.y: continue
			if g.would_win_game(c,k,enemy): score -= 250000
			elif g.would_claim(c,k,enemy): score -= 650 + board_value(g,c,enemy)*12
			if g.would_claim(c,k,p): score -= 65 # opponent can occupy our threat
	var mask: int = g.x_masks[b] if p == 1 else g.o_masks[b]
	var other: int = g.o_masks[b] if p == 1 else g.x_masks[b]
	for line in Rules.MASKS:
		if line & (1 << c) and line & other == 0:
			score += 18 + bit_count(mask & line)*30
	score += [12,3,12,3,22,3,12,3,12][c] + importance*2
	return score
static func bit_count(mask: int) -> int:
	var count = 0
	while mask: count += 1; mask &= mask-1
	return count
func board_value(g, b: int, p: int) -> float:
	var value = 3.0 if b == 4 else (2.0 if b%2 == 0 else 1.0)
	for line in Rules.LINES:
		if not b in line: continue
		var owned = 0; var blocked = false
		for i in line:
			if g.owners[i] == p: owned += 1
			elif g.owners[i] != 0: blocked = true
		if not blocked: value += [2,15,130,200][owned]
	return value
func evaluate(g, p: int) -> float:
	var value = 0.0
	for b in range(9):
		if g.owners[b] == p: value += 800 + board_value(g,b,p)*6
		elif g.owners[b] == 3-p: value -= 800 + board_value(g,b,3-p)*6
		elif g.owners[b] == 0:
			var mine: int = g.x_masks[b] if p == 1 else g.o_masks[b]
			var theirs: int = g.o_masks[b] if p == 1 else g.x_masks[b]
			for line in Rules.MASKS:
				if line & theirs == 0: value += [0,4,30,500][bit_count(line & mine)] * (1+board_value(g,b,p)*.025)
				if line & mine == 0: value -= [0,4,35,500][bit_count(line & theirs)] * (1+board_value(g,b,3-p)*.025)
	for line in Rules.LINES:
		var mine = 0; var theirs = 0; var blocked = false
		for b in line:
			if g.owners[b] == p: mine += 1
			elif g.owners[b] == 3-p: theirs += 1
			elif g.owners[b] == 3: blocked = true
		if blocked: continue
		if theirs == 0: value += [0,120,4000,100000][mine]
		if mine == 0: value -= [0,120,4400,100000][theirs]
	return value

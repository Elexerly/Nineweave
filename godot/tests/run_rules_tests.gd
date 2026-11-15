extends SceneTree
const Rules = preload("res://kernel/rules.gd")
const F = preload("res://tests/fixtures.gd")
var checks = 0
var failures = 0
func ok(value: bool, msg: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",msg)
func _initialize(): run.call_deferred()
func run():
	var g = Rules.new()
	ok(g.legal_moves().size() == 81 and g.turn == 1 and g.active_board == -1,"new game")
	ok(g.play(0,4) and g.active_board == 4 and g.turn == 2,"send to center")
	var before = g.compact()
	for m in [Vector2i(-1,0),Vector2i(9,0),Vector2i(4,9),Vector2i(0,0)]: ok(not g.play(m.x,m.y) and before == g.compact(),"illegal mutation-free "+str(m))
	ok(g.play(4,0),"reply routes back")
	ok(not g.play(0,4),"occupied cell")
	for line in Rules.LINES:
		for player in [1,2]:
			var chars = "........."
			var mark = "X" if player == 1 else "O"
			chars[line[0]] = mark; chars[line[1]] = mark
			var patterns = [chars,".........",".........",".........",".........",".........",".........",".........","........."]
			g = F.position(patterns,player,0)
			ok(g.play(0,line[2]) and g.owners[0] == player and line in g.winning_lines(0),"small line "+str(line)+" p"+str(player))
			ok(not g.is_legal(0,3),"claimed board closed")
			g = Rules.new(); patterns = []
			for b in range(9): patterns.append(".........")
			patterns[line[0]] = "XXXOO...." if player == 1 else "OOOXX...."
			patterns[line[1]] = patterns[line[0]]
			patterns[line[2]] = "XX.OO...." if player == 1 else "OO.XX...."
			g = F.position(patterns,player,line[2])
			ok(g.play(line[2],2) and g.winner() == player and line in g.big_lines,"big line "+str(line))
			ok(g.legal_moves().is_empty() and not g.play(8,8),"terminal no moves")
	g = F.position(["XXOOXXXO.",".........",".........",".........",".........",".........",".........",".........","........."],2,0)
	ok(g.play(0,8) and g.owners[0] == 3 and g.small_lines[0].is_empty(),"small draw closed")
	g = F.position(["XXXOO....",".........",".........",".........",".........",".........",".........",".........","........."],2,4)
	ok(g.play(4,0) and g.active_board == -1 and g.legal_moves().size() == 71,"won target allows any open")
	g = F.position(["XXOOXXXOO",".........",".........",".........",".........",".........",".........",".........","........."],1,4)
	ok(g.play(4,0) and g.active_board == -1,"drawn target allows any open")
	g = F.position(["XXXOO....","OOOXX....","XXXOO....","XXXOO....","OOOXX....","OOOXX....","OOOXX....","XXXOO....","XX.OO...."],1,8)
	ok(g.play(8,2) and g.status == 3 and g.winner() == 0,"big draw, unequal count has no tiebreak")
	# Multi-line win (center completes two diagonals).
	g = F.position(["XOXO.OXOX",".........",".........",".........",".........",".........",".........",".........","........."],1,0)
	ok(g.play(0,4) and g.small_lines[0].size() == 2,"all simultaneous winning lines")
	var random = RandomNumberGenerator.new(); random.seed = 972119
	var total_moves = 0
	for trial in range(2400):
		g = Rules.new()
		var snapshots = [g.compact()]
		while g.status == 0:
			var moves = g.legal_moves()
			ok(not moves.is_empty(),"ongoing has legal moves")
			var m = moves[random.randi_range(0,moves.size()-1)]
			var turn = g.turn
			ok(g.play(m.x,m.y),"fuzz legal accepted")
			ok(g.turn == 3-turn and g.history.size() <= 81,"alternation/history bound")
			ok(g.active_board == -1 or g.owners[g.active_board] == 0,"active always open")
			for b in range(9):
				ok(g.counts[b] == RulesCount(g,b),"cell counts consistent")
				ok((g.x_masks[b] & g.o_masks[b]) == 0,"disjoint bitboards")
			total_moves += 1
			if trial < 30: snapshots.append(g.compact())
		if trial < 30:
			var restored = Rules.new()
			ok(restored.deserialize(g.compact()) and restored.compact() == g.compact(),"serialize round trip")
			var final_cells = g.cells.duplicate()
			var count = g.history.size()
			for i in range(count):
				ok(g.undo(),"undo full history")
				var expected = JSON.parse_string(snapshots[count-i-1])
				ok(g.serialize().cells == expected.cells and g.active_board == expected.active and g.turn == expected.turn,"undo exact state")
			ok(not g.undo(),"undo empty")
			var redo_restore = Rules.new()
			ok(redo_restore.deserialize(g.compact()),"redo history serializes")
			for i in range(count): ok(g.redo() and redo_restore.redo(),"redo full history")
			ok(g.cells == final_cells and redo_restore.cells == final_cells,"redo integrity")
			ok(not g.redo(),"redo empty")
	g = Rules.new(); before = g.compact()
	for bad in ["bad",{}, {"v":1,"cells":"Z".repeat(81),"turn":1,"active":-1},{"v":1,"cells":".".repeat(81),"turn":1,"active":12}]:
		ok(not g.deserialize(bad) and g.compact() == before,"bad import transactional")
	print("NINEWEAVE_RULES ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures," fuzz_games=2400 fuzz_moves=",total_moves)
	quit(0 if failures == 0 else 1)
func RulesCount(g,b):
	var total = 0
	for c in range(9):
		if g.cells[b*9+c] != 0: total += 1
	return total

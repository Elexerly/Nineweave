extends SceneTree
const R = preload("res://kernel/rules.gd")
const AI = preload("res://ai/strategist.gd")
const F = preload("res://tests/fixtures.gd")
var checks = 0
var failures = 0
var timings: Array = []
func ok(value: bool, msg: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",msg)
func _initialize(): run.call_deferred()
func run():
	var random = RandomNumberGenerator.new(); random.seed = 19817
	var g = R.new()
	for round_index in range(45):
		for level in ["Easy","Medium","Hard"]:
			var ai = AI.new(500+round_index); ai.node_limit = 700
			var move = ai.choose_move(g,level)
			ok(g.is_legal(move.x,move.y),"legal "+level+" at ply "+str(round_index))
			ok(ai.elapsed_ms <= ai.budget_ms+40,"time ceiling "+level)
			if level == "Hard": timings.append(ai.elapsed_ms)
		var moves = g.legal_moves()
		var m = moves[random.randi_range(0,moves.size()-1)]; g.play(m.x,m.y)
		if g.status != 0: g.new_game()
	for player in [1,2]:
		g = F.big_tactic(player)
		var ai = AI.new(124)
		var m = ai.choose_move(g,"Hard")
		ok(m == Vector2i(2,2),"Hard takes immediate GAME win player "+str(player))
		g = F.big_tactic(player,true)
		m = ai.choose_move(g,"Hard")
		ok(g.play(m.x,m.y),"block legal")
		var immediate_loss = false
		for reply in g.legal_moves():
			if g.would_win_game(reply.x,reply.y,g.turn): immediate_loss = true
		ok(not immediate_loss,"Hard blocks immediate GAME loss player "+str(3-player))
	g = R.new(); g.play(4,4); g.play(4,0)
	var a = AI.new(718); var b = AI.new(718)
	a.node_limit = 700; b.node_limit = 700
	ok(a.choose_move(g,"Hard") == b.choose_move(g,"Hard") and a.nodes == b.nodes,"seeded deterministic search")
	# Incremental mode leaves the match untouched and returns the synchronous move.
	var saved = g.compact(); a.begin(g,"Hard",123)
	var slices = 0
	while not a.done: a.step(2500); slices += 1
	ok(g.compact() == saved and g.is_legal(a.best_move.x,a.best_move.y),"incremental isolation")
	ok(a.max_slice_ms < 80,"incremental slice does not freeze animations")
	print("AI incremental slices=",slices," max_slice_ms=",snappedf(a.max_slice_ms,.01))
	# Alternating seats, fixed seeds, real games from empty board. Draws aren't wins.
	var n = 30
	for level in ["Medium","Hard"]:
		var wins = 0; var draws = 0; var losses = 0; var moves_count = 0
		for trial in range(n):
			g = R.new(); var strong_seat = 1+trial%2
			var strong = AI.new(2000+trial); var easy = AI.new(9000+trial)
			strong.node_limit = 700
			while g.status == 0:
				var m = strong.choose_move(g,level) if g.turn == strong_seat else easy.choose_move(g,"Easy")
				ok(g.play(m.x,m.y),"match move legal")
				moves_count += 1
			if g.status == strong_seat: wins += 1
			elif g.status == 3: draws += 1
			else: losses += 1
		print("AI_STRENGTH ",level," vs Easy N=",n," wins=",wins," draws=",draws," losses=",losses," rate=",100.0*wins/n,"% moves=",moves_count," node_limit=700")
		ok(wins >= ceili(n*.9) if level == "Hard" else wins > n/2,"strength requirement "+level)
	var total = 0.0; var maximum = 0.0
	for t in timings: total += t; maximum = maxf(maximum,t)
	print("AI_TIMING Hard samples=",timings.size()," mean_ms=",snappedf(total/timings.size(),.01)," max_ms=",snappedf(maximum,.01)," hard_ceiling_ms=450")
	print("NINEWEAVE_AI ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

extends RefCounted
## Portable single-elimination model. IDs are opaque; no AI, storage or transport.
## A result can come from a local match or a live waiting-room update.
static func generate(entrants: Array, seed_value: int, focus_id: String = "", opposite_id: String = "") -> Dictionary:
	if entrants.size() < 3 or entrants.size() > 8: return {}
	var ids: Array = []; var people: Dictionary = {}
	for entrant in entrants:
		if not entrant is Dictionary or not entrant.has("id") or str(entrant.id).is_empty() or people.has(str(entrant.id)): return {}
		var id = str(entrant.id); ids.append(id); people[id] = entrant.duplicate(true)
	var rng = RandomNumberGenerator.new(); rng.seed = seed_value
	for i in range(ids.size()-1,0,-1):
		var j = rng.randi_range(0,i); var temp = ids[i]; ids[i] = ids[j]; ids[j] = temp
	var capacity = 4 if ids.size() <= 4 else 8
	# Fill one entrant in each match before assigning opponents: never empty vs empty.
	var slots: Array = []; slots.resize(capacity); slots.fill("")
	for i in range(ids.size()): slots[(i*2)%capacity+int(i/(capacity/2))] = ids[i]
	if focus_id in slots and opposite_id in slots:
		var player = slots.find(focus_id); var rival = slots.find(opposite_id)
		if int(player/(capacity/2)) == int(rival/(capacity/2)):
			var target = (rival+capacity/2)%capacity
			var temp = slots[target]; slots[target] = opposite_id; slots[rival] = temp
	var rounds: Array = []; var count = capacity/2
	while count >= 1:
		var matches: Array = []
		for i in range(count): matches.append({"id":"r%d-m%d" % [rounds.size(),i],"a":"","b":"","winner":"","resolved":false,"bye":false})
		rounds.append(matches); count = int(count/2)
	for i in range(capacity/2): rounds[0][i].a = slots[i*2]; rounds[0][i].b = slots[i*2+1]
	var model = {"version":1,"seed":seed_value,"entrants":people,"rounds":rounds,"focus_id":focus_id,"champion":""}
	advance_byes(model)
	return model

static func apply_result(model: Dictionary, round_index: int, match_index: int, winner: String) -> Dictionary:
	if model.is_empty() or round_index < 0 or round_index >= model.rounds.size(): return {}
	if match_index < 0 or match_index >= model.rounds[round_index].size(): return {}
	var game: Dictionary = model.rounds[round_index][match_index]
	if game.resolved or game.a.is_empty() or game.b.is_empty() or not winner in [game.a,game.b]: return {}
	var event = {"round":round_index,"index":match_index,"winner":winner,"loser":game.b if winner == game.a else game.a}
	_resolve(model,round_index,match_index,winner,false)
	advance_byes(model)
	return event

static func _resolve(model: Dictionary, round_index: int, index: int, winner: String, bye: bool):
	var game: Dictionary = model.rounds[round_index][index]
	game.winner = winner; game.resolved = true; game.bye = bye
	if round_index+1 < model.rounds.size():
		model.rounds[round_index+1][int(index/2)]["a" if index%2 == 0 else "b"] = winner
	else: model.champion = winner

static func advance_byes(model: Dictionary):
	for r in range(model.rounds.size()):
		for i in range(model.rounds[r].size()):
			var game: Dictionary = model.rounds[r][i]
			if game.resolved: continue
			var ready = r == 0 or (model.rounds[r-1][i*2].resolved and model.rounds[r-1][i*2+1].resolved)
			if ready and (game.a.is_empty() != game.b.is_empty()): _resolve(model,r,i,game.b if game.a.is_empty() else game.a,true)

static func next_match(model: Dictionary, id: String) -> Dictionary:
	if model.is_empty(): return {}
	for r in range(model.rounds.size()):
		for i in range(model.rounds[r].size()):
			var game: Dictionary = model.rounds[r][i]
			if not game.resolved and id in [game.a,game.b] and not game.a.is_empty() and not game.b.is_empty():
				return {"round":r,"index":i,"match":game}
	return {}

static func eliminated(model: Dictionary, id: String) -> bool:
	for round_matches in model.get("rounds",[]):
		for game in round_matches:
			if game.resolved and not game.bye and id in [game.a,game.b] and game.winner != id: return true
	return false

static func round_name(model: Dictionary, index: int) -> String:
	return ["Final","Semifinal","Quarterfinal"][clampi(model.rounds.size()-1-index,0,2)]

static func valid(model: Dictionary) -> bool:
	# Reconstruct and replay instead of trusting save-file topology or winners.
	if model.get("version") != 1 or not model.get("entrants") is Dictionary or not model.get("rounds") is Array: return false
	if not model.get("seed") is int or not model.get("focus_id") is String: return false
	var rebuilt = generate(model.entrants.values(),model.seed,model.focus_id)
	if rebuilt.is_empty() or rebuilt.rounds.size() != model.rounds.size(): return false
	if not model.rounds[0] is Array: return false
	var seen: Array = []; var first: Array = model.rounds[0]
	if first.size() != rebuilt.rounds[0].size(): return false
	for game in first:
		if not game is Dictionary or not game.get("a") is String or not game.get("b") is String: return false
		for id in [game.a,game.b]:
			if id.is_empty(): continue
			if id in seen or not model.entrants.has(id): return false
			seen.append(id)
	if seen.size() != model.entrants.size(): return false
	# Seed ordering can include a rival swap; validate against the saved first round.
	for i in range(first.size()):
		rebuilt.rounds[0][i] = {"id":"r0-m%d" % i,"a":first[i].a,"b":first[i].b,"winner":"","resolved":false,"bye":false}
	for r in range(1,rebuilt.rounds.size()):
		for game in rebuilt.rounds[r]: game.a = ""; game.b = ""; game.winner = ""; game.resolved = false; game.bye = false
	rebuilt.champion = ""; advance_byes(rebuilt)
	for r in range(model.rounds.size()):
		if not model.rounds[r] is Array or model.rounds[r].size() != rebuilt.rounds[r].size(): return false
		for i in range(model.rounds[r].size()):
			var game = model.rounds[r][i]
			if not game is Dictionary or not game.has_all(["a","b","winner","resolved","bye","id"]): return false
			if not game.resolved is bool or not game.bye is bool or not game.winner is String: return false
			if game.resolved and not rebuilt.rounds[r][i].resolved:
				if apply_result(rebuilt,r,i,game.winner).is_empty(): return false
			if game != rebuilt.rounds[r][i]: return false
	return model.get("champion","") == rebuilt.champion

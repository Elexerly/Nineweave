extends RefCounted
## Pure transition detector. Most specific event first; all qualifying events retained
## for tests/telemetry. Presentation selects one line so claims never become a queue.
const Rules = preload("res://kernel/rules.gd")
const TEXT = {"ready":"READY…", "weave":"WEAVE!", "victory":"VICTORY!", "defeat":"DEFEAT!", "first_claim":"FIRST CLAIM!", "double_lock":"DOUBLE LOCK!", "triple_weave":"TRIPLE WEAVE!", "match_point":"MATCH POINT!", "turnaround":"TURNAROUND!", "shutout":"SHUTOUT!", "nineweave":"LEXERLY!", "clean_sweep":"CLEAN SWEEP!", "standoff":"STANDOFF!"}
const WEIGHT = {"ready":1,"weave":2,"victory":5,"defeat":3,"first_claim":2,"double_lock":3,"triple_weave":4,"match_point":4,"turnaround":5,"shutout":5,"nineweave":6,"clean_sweep":7,"standoff":2}
static func snapshot(game) -> Dictionary:
	return {"owners":Array(game.owners),"status":game.status,"turn":game.turn,"moves":game.history.size()}
static func threats(owners: Array, player: int) -> Array:
	var result: Array = []
	for line in Rules.LINES:
		var count = 0; var empty = -1
		for b in line:
			if owners[b] == player: count += 1
			elif owners[b] == 0: empty = b
		if count == 2 and empty >= 0 and not result.has(empty): result.append(empty)
	return result
static func turned_around(before: Array, after: Array, player: int) -> bool:
	return before.count(player) < before.count(3-player) and after.count(player) >= after.count(3-player)
static func events(previous: Dictionary, current: Dictionary) -> Array:
	if previous.is_empty(): return ["ready"]
	if previous.status != 0: return []
	if current.status == 3: return ["standoff"]
	if current.status in [1,2]:
		return ["clean_sweep","nineweave"] if current.owners.count(3-int(current.status)) == 0 else ["nineweave"]
	var p = int(previous.turn); var b = -1
	for i in range(9):
		if previous.owners[i] == 0 and current.owners[i] == p: b = i; break
	if b < 0: return []
	var found: Array = []
	if b in threats(previous.owners,3-p): found.append("shutout")
	# Round 3c: only a claim that takes the mover from behind to level/ahead. Blocking a
	# threat is SHUTOUT; a claim that still leaves you behind is not a turnaround.
	if turned_around(previous.owners,current.owners,p): found.append("turnaround")
	if not threats(current.owners,p).is_empty() and threats(previous.owners,p).is_empty(): found.append("match_point")
	var count = current.owners.count(p)
	if count == 3: found.append("triple_weave")
	elif count == 2: found.append("double_lock")
	elif previous.owners.count(1)+previous.owners.count(2) == 0: found.append("first_claim")
	return found
static func detect(previous: Dictionary, current: Dictionary) -> String:
	var found = events(previous,current)
	return str(found[0]) if not found.is_empty() else ""

extends RefCounted
## Maps the server's authoritative seeds and results into Round 5b's BracketView.
## Never generate/reseed/resolve an online bracket locally.
static func person_id(person) -> String:
	if not person is Dictionary: return ""
	return "seed:%d" % int(person.seed) if person.get("seed") != null else "name:"+str(person.get("name",""))
static func from_envelope(data: Dictionary) -> Dictionary:
	var people = {}
	for person in data.get("players",[]):
		if person is Dictionary:
			people[person_id(person)] = {"id":person_id(person),"name":str(person.get("name","Player")),"hero_id":str(person.get("hero","")),"eliminated":bool(person.get("eliminated",false))}
	var rounds: Array = []
	for r in range(data.get("rounds",[]).size()):
		var matches: Array = []
		for game in data.rounds[r]:
			var a = person_id(game.get("a")); var b = person_id(game.get("b"))
			var winner = a if game.get("winner") == "a" else (b if game.get("winner") == "b" else "")
			matches.append({"id":"r%d-m%d" % [r,int(game.get("slot",matches.size()))],"a":a,"b":b,"winner":winner,
				"resolved":game.get("status") == "done","bye":bool(game.get("bye",false)),"status":str(game.get("status","pending")),
				"score":game.get("score"),"end_reason":game.get("end_reason")})
		rounds.append(matches)
	var focus = person_id(data.get("you")); var champion = ""
	if not rounds.is_empty() and not rounds.back().is_empty(): champion = str(rounds.back()[0].winner)
	return {"version":1,"entrants":people,"rounds":rounds,"focus_id":focus,"champion":champion}
static func result_events(previous: Dictionary, current: Dictionary) -> Array:
	var events: Array = []
	if previous.is_empty(): return events
	for r in range(current.rounds.size()):
		for i in range(current.rounds[r].size()):
			var game = current.rounds[r][i]
			var old = previous.rounds[r][i] if r < previous.rounds.size() and i < previous.rounds[r].size() else {}
			if game.resolved and not old.get("resolved",false) and not game.winner.is_empty():
				events.append({"round":r,"index":i,"winner":game.winner,"loser":game.b if game.winner == game.a else game.a})
	return events

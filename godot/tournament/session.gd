extends RefCounted
const AppEnvironment = preload("res://net/game_environment.gd")
## Local tournament policy + one atomic save. No network dependencies.
const Bracket = preload("res://tournament/bracket.gd")
const Roster = preload("res://characters/roster.gd")
## Patrick's confirmed chess rivalry. Add future pairs here, symmetrically.
const RIVALS = {"shard_jack":"james_ii","james_ii":"shard_jack"}
const LEVELS = ["Easy","Medium","Hard"]
var path: String
var active: Dictionary = {}
var wins: Dictionary = {}
var last_events: Array = []
func _init(save_path: String = ""):
	path = AppEnvironment.save_path("nineweave-tournament.cfg") if save_path.is_empty() else save_path
	var cfg = ConfigFile.new()
	if FileAccess.file_exists(path) and not FileAccess.get_file_as_bytes(path).has(0) and cfg.load(path) == OK:
		var counts = cfg.get_value("tournament","wins",{})
		if counts is Dictionary:
			for id in counts:
				if Roster.valid(str(id)) and counts[id] is int and counts[id] > 0: wins[str(id)] = counts[id]
		var saved = cfg.get_value("tournament","active",{})
		if _valid_active(saved): active = saved
func _valid_active(saved) -> bool:
	if not saved is Dictionary or saved.is_empty(): return false
	if not saved.get("hero") is String or not Roster.valid(saved.hero) or not saved.get("model") is Dictionary: return false
	if not saved.get("status") in ["bracket","eliminated","champion"] or not saved.get("round") is int or not saved.get("awarded") is bool: return false
	if saved.round < 0 or saved.round > 2 or not saved.get("rival") is String or saved.rival != RIVALS.get(saved.hero,""): return false
	if not Bracket.valid(saved.model) or saved.model.focus_id != saved.hero or not saved.model.entrants.has(saved.hero): return false
	if saved.model.entrants.size() != 8: return false
	for entrant in saved.model.entrants.values():
		if not entrant.get("hero_id") is String or not Roster.valid(entrant.hero_id): return false
	if saved.status == "champion": return saved.model.champion == saved.hero and saved.awarded
	if saved.status == "eliminated": return Bracket.eliminated(saved.model,saved.hero)
	var next = Bracket.next_match(saved.model,saved.hero)
	return not saved.awarded and not Bracket.eliminated(saved.model,saved.hero) and saved.model.champion.is_empty() and not next.is_empty() and next.round == saved.round
func create(hero: String, seed_value: int = -1):
	if not Roster.valid(hero): return
	hero = Roster.canonical_id(hero)
	if seed_value < 0: seed_value = int(Time.get_ticks_usec()) ^ int(Time.get_unix_time_from_system()) ^ randi()
	var rng = RandomNumberGenerator.new(); rng.seed = seed_value
	var available: Array = []
	var rival: String = RIVALS.get(hero,"")
	for entry in Roster.DATA:
		if not entry.id in [hero,rival] and not entry.get("secret",false): available.append(entry.id)
	var chosen: Array = [hero]
	if not rival.is_empty(): chosen.append(rival)
	while chosen.size() < 8: chosen.append(available.pop_at(rng.randi_range(0,available.size()-1)))
	var entrants: Array = []
	for id in chosen: entrants.append({"id":id,"hero_id":id,"name":Roster.get_hero(id).name})
	active = {"hero":hero,"rival":rival,"model":Bracket.generate(entrants,seed_value,hero,rival),"round":0,"status":"bracket","awarded":false}
	last_events = []; save()
func level() -> String: return LEVELS[clampi(int(active.get("round",0)),0,2)]
func current() -> Dictionary: return Bracket.next_match(active.model,active.hero) if not active.is_empty() and active.status == "bracket" else {}
func opponent() -> String:
	var match_data = current()
	if match_data.is_empty(): return ""
	return match_data.match.b if match_data.match.a == active.hero else match_data.match.a
func cpu_winner(model: Dictionary, r: int, i: int, rival: String) -> String:
	var match_data: Dictionary = model.rounds[r][i]
	var rng = RandomNumberGenerator.new(); rng.seed = int(model.seed)+r*104729+i*1543+8191
	var chance = .78 if match_data.a == rival else (.22 if match_data.b == rival else .5)
	return match_data.a if rng.randf() < chance else match_data.b
func finish(won: bool) -> bool:
	var next = current()
	if next.is_empty(): return false
	last_events = []
	var hero: String = active.hero
	var event = Bracket.apply_result(active.model,next.round,next.index,hero if won else opponent())
	if event.is_empty(): return false
	last_events.append(event)
	for i in range(active.model.rounds[next.round].size()):
		var game: Dictionary = active.model.rounds[next.round][i]
		if game.resolved: continue
		last_events.append(Bracket.apply_result(active.model,next.round,i,cpu_winner(active.model,next.round,i,str(active.rival))))
	if not won: active.status = "eliminated"
	elif active.model.champion == hero:
		active.status = "champion"
		if not active.awarded: wins[hero] = int(wins.get(hero,0))+1; active.awarded = true
	else: active.round += 1
	save(); return true
func total_trophies() -> int:
	var total = 0
	for count in wins.values(): total += int(count)
	return total
func abandon(): active = {}; last_events = []; save()
func save() -> bool:
	var cfg = ConfigFile.new(); cfg.set_value("tournament","version",1)
	cfg.set_value("tournament","active",active); cfg.set_value("tournament","wins",wins)
	if cfg.save(path+".tmp") != OK: return false
	return DirAccess.rename_absolute(path+".tmp",path) == OK

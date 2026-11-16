extends RefCounted
## Round 5a: pure timing, polling and copy helpers for protocol-2 rooms. The server
## enforces every deadline; these only turn envelope fields into what the client shows.
const TURN_SECONDS = 25.0
const STILL_THERE_SECONDS = 10.0
## Ring turns amber, then red, inside the last seconds of the 25-second turn.
const AMBER_AT = 8.0
const RED_AT = 3.0
const HIDDEN_POLL_MS = 5000
const CHAT_LIMIT = 120
const NOTE_LIMIT = 500
const REPORT_REASONS = [["harassment","Harassment"],["hate","Hate"],["inappropriate_name","Inappropriate name"],["cheating","Cheating"],["spam","Spam"],["other","Other"]]
const DEFAULT_PRESETS = {"gg":"Good game!","nice":"Nice move","rematch":"Rematch?","gl":"Good luck!","hi":"Hi!","thanks":"Thanks!","wow":"Wow!","oops":"Oops!"}

## ISO-8601 UTC ("2026-11-15T12:00:25.250Z") to unix seconds, keeping fractions. 0 = invalid.
static func parse(iso) -> float:
	if not iso is String or iso.length() < 19: return 0.0
	var text: String = iso.strip_edges().trim_suffix("Z")
	var plus = text.find("+", 19)
	if plus > 0: text = text.left(plus)
	var parts = text.split(".")
	var whole = Time.get_unix_time_from_datetime_string(parts[0])
	if whole <= 0: return 0.0
	var fraction = 0.0
	if parts.size() > 1 and parts[1].is_valid_int(): fraction = float("0."+parts[1])
	return float(whole)+fraction
## Server minus device clock, from the envelope's server_now at the moment it arrived.
static func offset(server_now, local_now: float) -> float:
	var stamp = parse(server_now)
	return stamp-local_now if stamp > 0 else 0.0
## Seconds until `deadline` on the server clock, counted down locally.
static func remaining(deadline, clock_offset: float, local_now: float) -> float:
	var at = parse(deadline)
	if at <= 0: return -1.0
	return at-(local_now+clock_offset)
## Turn presentation for the active seat. Phases: none, legacy (old server: plain
## countdown to turn_expires_at), turn (25 s ring), still_there (10 s prompt), expired.
static func phase(room: Dictionary, seat: int, clock_offset: float, local_now: float) -> Dictionary:
	var state = room.get("state",{})
	var turn = int(state.get("turn",0)) if state is Dictionary else 0
	var info = {"phase":"none","mine":turn == seat and seat in [1,2],"remaining":0.0,"fraction":0.0,"tier":"calm","turn":turn}
	if str(room.get("status","")) != "active": return info
	var now = local_now+clock_offset
	var still = parse(room.get("still_there_at"))
	var expires = parse(room.get("turn_expires_at"))
	if still <= 0:
		if expires > 0:
			info.phase = "legacy"; info.remaining = maxf(0,expires-now)
		return info
	var turn_seconds = _positive(room.get("turn_seconds"),TURN_SECONDS)
	var prompt_seconds = _positive(room.get("still_there_seconds"),STILL_THERE_SECONDS)
	if expires <= 0: expires = still+prompt_seconds
	if now < still:
		info.phase = "turn"; info.remaining = still-now
		info.fraction = clampf(info.remaining/turn_seconds,0,1)
		info.tier = "calm" if info.remaining > AMBER_AT else ("amber" if info.remaining > RED_AT else "red")
	elif now < expires:
		info.phase = "still_there"; info.remaining = expires-now
		info.fraction = clampf(info.remaining/prompt_seconds,0,1); info.tier = "red"
	else:
		info.phase = "expired"; info.tier = "red"
	return info
static func _positive(value, fallback: float) -> float:
	return float(value) if (value is int or value is float) and float(value) > 0 else fallback
static func tier_color(tier: String) -> Color:
	match tier:
		"amber": return Color("ff8a1c")
		"red": return Color("ff3b30")
	return Color("42dcff")
## "0:08" — whole seconds, rounded up so 0:00 only shows at the deadline.
static func mmss(seconds: float) -> String:
	var s = maxi(0,ceili(seconds-0.001))
	return "%d:%02d" % [s/60,s%60]

## Next poll in ms. 0 stops polling. poll_after_ms wins; old servers get the documented
## fallbacks. A hidden tab or backgrounded app slows to 5 s but never stops.
static func poll_ms(room: Dictionary, seat: int, hidden: bool) -> int:
	var hint = room.get("poll_after_ms")
	var ms: int
	if hint is int or hint is float: ms = int(hint)
	else:
		match str(room.get("status","")):
			"waiting": ms = 3000
			"active":
				var state = room.get("state",{})
				ms = 3000 if state is Dictionary and int(state.get("turn",0)) == seat else 1500
			"finished": ms = 4000
			"closed": ms = 0
			_: ms = 3000
	if ms <= 0: return 0
	return maxi(ms,HIDDEN_POLL_MS) if hidden else ms
## Retry delay after consecutive failed polls: 1, 2, 4, then 5 s (well inside the 60 s grace).
static func backoff_ms(failures: int) -> int:
	return mini(1000*int(pow(2,maxi(0,failures-1))),5000)

## Single line, collapsed whitespace, at most 120 characters (the server masks the rest).
static func clean_chat(text: String) -> String:
	var out = ""
	var space = false
	for ch in text:
		var code = ch.unicode_at(0)
		if code < 32 or code == 127 or ch == " " or (code >= 0x200B and code <= 0x200F) or (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069) or code == 0xFEFF:
			if code < 32 or ch == " " or code == 127: space = true
			continue
		if space and not out.is_empty(): out += " "
		space = false; out += ch
	return out.left(CHAT_LIMIT)

## Opponent's display name: protocol-2 `players`, else the round 1–4 `opponent` string.
static func opponent_name(data: Dictionary, seat: int) -> String:
	var players = data.get("players")
	if players is Dictionary and seat in [1,2]:
		var other = players.get(str(3-seat))
		if other is Dictionary and other.get("name") is String and not str(other.name).strip_edges().is_empty(): return str(other.name)
	var legacy = data.get("opponent")
	return str(legacy) if legacy is String else ""
static func opponent_hero(data: Dictionary, seat: int) -> String:
	var players = data.get("players")
	if players is Dictionary and seat in [1,2]:
		var other = players.get(str(3-seat))
		if other is Dictionary and other.get("hero") is String: return str(other.hero)
	return ""

## Leave confirmation copy. Unknown both_moved (old server) is treated as a recorded loss.
static func leave_copy(costs_loss: bool) -> String:
	return "Leave match? This counts as a loss." if costs_loss else "Leave match? No one gets a loss yet."
## End-of-match line for a closed room. `winner` is a seat (0 draw, -1 none).
static func end_text(reason: String, winner: int, seat: int, opponent_left: bool, name: String) -> String:
	var who = name if not name.strip_edges().is_empty() else "Your opponent"
	var won = winner == seat and seat in [1,2]
	match reason:
		"no_show":
			return who+" didn't show up — match cancelled, no loss" if opponent_left else "You didn't move in time — match cancelled, no loss"
		"cancelled":
			return who+" left — match cancelled, no loss" if opponent_left else "Match cancelled — no loss"
		"forfeit":
			return who+" left — you win" if won else "You left — this counts as a loss"
		"timeout":
			return who+" ran out of time — you win" if won else "Time ran out — you lose"
		"abandoned":
			return who+" disconnected — you win" if won else "Connection lost — you lose"
		"expired":
			return "This room expired — no result"
	return ""
## Title for the cancelled-match card (no recorded result).
static func cancelled_title(reason: String) -> String:
	return "ROOM EXPIRED" if reason == "expired" else "MATCH CANCELLED"

## Only http(s)://localhost or 127.0.0.1 (optional port), and only on a local page.
static func api_override(hostname: String, value: String) -> String:
	if hostname not in ["localhost","127.0.0.1"]: return ""
	var regex = RegEx.create_from_string("^https?://(localhost|127\\.0\\.0\\.1)(:[0-9]{1,5})?/?$")
	var clean = value.strip_edges()
	if regex.search(clean) == null: return ""
	return clean.trim_suffix("/")

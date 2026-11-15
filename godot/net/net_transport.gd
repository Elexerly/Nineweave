class_name NetTransport
extends Node
## All moves are server acknowledgements; clients never commit speculative moves.
const Roster = preload("res://characters/roster.gd")
signal character_received(seat: int, character_id: String)
signal connected
signal room_created(code: String)
signal joined(code: String, seat: int)
signal opponent_joined
signal move_received(board: int, cell: int, seq: int)
signal state_received(state: Dictionary, seq: int)
signal opponent_left
signal error(message: String)
var player_name: String = "Wanderer"
var remote_name: String = "Remote player"
var seat: int = 0
var code: String = ""
func create_room() -> void: error.emit("Transport unavailable")
func join_room(_code: String) -> void: error.emit("Transport unavailable")
func send_move(_board: int, _cell: int, _seq: int) -> void: pass
func leave() -> void: pass

# Character identity is the only shared cosmetic. No theme/background is accepted.
var character_id: String = "vesper_vale"
var remote_character_id: String = "auric_rex"
func character_payload() -> Dictionary:
	return {"character_id":character_id if Roster.valid(character_id) else "vesper_vale"}
func lobby_payload() -> Dictionary:
	var payload = character_payload(); payload["name"] = player_name.left(24); return payload
func receive_characters(characters: Dictionary) -> bool:
	for key in characters:
		if str(key) not in ["1","2"] or not Roster.valid(str(characters[key])):
			error.emit("Unknown character in room response"); return false
	for key in characters:
		var mark = int(key); var id = str(characters[key])
		if mark != seat: remote_character_id = id
		character_received.emit(mark,id)
	return true

# Round 4: agreement and side assignment belong to the authoritative transport.
signal rematch_changed(local_agreed: bool, remote_agreed: bool)
signal match_started(assigned_seat: int, round_number: int)
var local_rematch: bool = false
var remote_rematch: bool = false
var match_round: int = 1
func request_rematch() -> void: error.emit("Rematch is not supported by this server yet")
func rematch_status() -> String:
	if local_rematch: return "WAITING FOR OPPONENT…"
	if remote_rematch: return "OPPONENT WANTS A REMATCH"
	return ""
func reset_agreement():
	local_rematch = false; remote_rematch = false
func receive_match_info(data: Dictionary):
	# Server supplies the client's seat and agreement flags; a local click cannot start a round.
	var next_round = int(data.get("round",match_round))
	var assigned = int(data.get("seat",seat))
	if next_round < match_round or assigned not in [1,2]: return
	if next_round > match_round:
		match_round = next_round; seat = assigned; reset_agreement(); match_started.emit(seat,match_round)
	else:
		local_rematch = bool(data.get("local",local_rematch)); remote_rematch = bool(data.get("remote",remote_rematch))
		rematch_changed.emit(local_rematch,remote_rematch)

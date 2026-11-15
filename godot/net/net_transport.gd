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

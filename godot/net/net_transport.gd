class_name NetTransport
extends Node
## All moves are server acknowledgements; clients never commit speculative moves.
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

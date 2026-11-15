class_name LoopbackTransport
extends "res://net/net_transport.gd"
## In-process authoritative room service. Clearly labelled LOCAL DEMO in UI.
const Rules = preload("res://kernel/rules.gd")
static var rooms: Dictionary = {}
static var next_room: int = 0
var _peer: WeakRef
func create_room() -> void:
	leave()
	next_room += 1
	code = "N%04d" % (next_room%10000)
	seat = 1
	rooms[code] = {"host":weakref(self),"guest":null,"game":Rules.new(),"seq":0,"characters":{"1":character_payload().character_id}}
	connected.emit(); room_created.emit(code); joined.emit(code,seat)
func join_room(room_code: String) -> void:
	room_code = room_code.strip_edges().to_upper()
	if not rooms.has(room_code): error.emit("Room not found. Check the five-character code."); return
	var room = rooms[room_code]
	var host = room.host.get_ref()
	if host == null or room.guest != null: error.emit("Room is full or has expired."); return
	code = room_code; seat = 2; room.guest = weakref(self); _peer = room.host
	host._peer = weakref(self)
	host.remote_name = player_name; remote_name = host.player_name
	room.characters["2"] = character_payload().character_id
	host.receive_characters(room.characters); receive_characters(room.characters)
	connected.emit(); joined.emit(code,seat)
	host.opponent_joined.emit(); opponent_joined.emit()
	state_received.emit(room.game.serialize(),room.seq)
func send_move(board: int, cell: int, seq: int) -> void:
	if not rooms.has(code): error.emit("Room closed"); return
	var room = rooms[code]
	if room.guest == null: error.emit("Waiting for opponent…"); return
	if seq != room.seq+1 or room.game.turn != seat or not room.game.play(board,cell):
		error.emit("Move rejected: stale sequence, wrong seat or illegal move")
		state_received.emit(room.game.serialize(),room.seq)
		return
	room.seq = seq
	# Broadcast the authoritative acknowledgement to BOTH clients.
	for client_ref in [room.host,room.guest]:
		var client = client_ref.get_ref() if client_ref != null else null
		if client != null: client.move_received.emit(board,cell,seq)
func leave() -> void:
	if code.is_empty(): return
	if rooms.has(code):
		var room = rooms[code]
		var other_ref = room.guest if seat == 1 else room.host
		if other_ref != null and other_ref.get_ref() != null: other_ref.get_ref().opponent_left.emit()
		rooms.erase(code)
	code = ""; seat = 0; _peer = null; remote_character_id = "auric_rex"
func _exit_tree(): leave()
static func reset_service(): rooms.clear(); next_room = 0

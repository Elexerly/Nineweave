extends SceneTree
## Production PCK smoke check without claiming a render. Supply this script by
## absolute path with --main-pack .godot/r5c/web/index.pck. No network is used.
const Main = preload("res://main/main.tscn")
const Roster = preload("res://characters/roster.gd")
const Art = preload("res://characters/art.gd")
class QuietHTTP extends Node:
	signal request_completed(result: int, response: int, headers: PackedStringArray, body: PackedByteArray)
	var timeout: float = 0
	func request(_url: String, _headers: PackedStringArray, _method: int, _body: String) -> int: return OK
	func cancel_request(): pass
var checks = 0
func verify(value: bool, label: String):
	checks += 1
	if not value: push_error("PACK ROUND5C FAIL: "+label); quit(1)
func _initialize(): run.call_deferred()
func run():
	var main = Main.instantiate(); main.test_online_bypass = true
	main.settings.path = "user://r5c-pack-settings.cfg"; main.profile.path = "user://r5c-pack-profile.cfg"
	main.settings.values.sound = false; main.settings.values.tutorial_completed = true
	# The web PCK deliberately has no clips; do not start sidecar downloads when
	# running it inside the native headless engine for this resource smoke check.
	main.hero_video.catalog = {}; main.hero_video.bundled_override = 1
	main.http_request_factory = func(): return QuietHTTP.new()
	root.add_child(main); main.set_process(false); main.online_tournament.set_process(false)
	main.tournament.session.abandon(); main.go_home(); main.set_view_size(Vector2(390,844))
	var textures = 0
	for hero in Roster.DATA:
		for key in ["splash","versus","victory","head_neutral","head_smug","head_panic","head_doubletake","head_eyeroll","head_cheer","head_pout"]:
			var texture = Art.get_texture(hero.id,key)
			verify(texture != null and texture.get_width() > 0,"packed texture "+hero.id+"/"+key); textures += 1
	main.controls.tournament.pressed.emit()
	verify(main.controls.has_all(["computer","online_tournament"]),"packed chooser")
	main.controls.online_tournament.pressed.emit()
	main.online_tournament.api._request.request_completed.emit(HTTPRequest.RESULT_SUCCESS,404,PackedStringArray(),'{"error":"Not found"}'.to_utf8_buffer())
	verify(main.online_tournament.unavailable and main.controls.has("computer"),"packed coming-soon fallback")
	main.controls.computer.pressed.emit(); main.hero_select._confirm()
	verify(main.page == "tournament","packed computer bracket")
	main.tournament.screen.bracket.seek(5); main.tournament.play()
	verify(main.cinematic.kind == "versus","packed versus")
	main.cinematic.advance(3.01); main.game.status = 2; main._show_spotlight()
	verify(main.cinematic.combined_result and main.controls.has_all(["again","menu"]),"packed combined winner and controls")
	verify(main.cinematic.winner_id == main.rival_character,"packed opponent victory identity")
	main.go_home(); main.free(); await process_frame
	print("NINEWEAVE_ROUND5C_PACK PASS checks=",checks," hero_textures=",textures," chooser/404/bracket/versus/combined-result=PASS (headless; no rendered claim)")
	quit()

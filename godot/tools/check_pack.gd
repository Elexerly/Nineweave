extends SceneTree
## Run against the exported PCK, with this script supplied as an absolute path.
## Checks release resource paths and production flow without pretending to render.
const Art = preload("res://characters/art.gd")
const Roster = preload("res://characters/roster.gd")
const Main = preload("res://main/main.tscn")
func _initialize(): run.call_deferred()
func run():
	var count = 0
	for hero in Roster.DATA:
		for key in ["splash","versus","victory","head_neutral","head_smug","head_panic","head_doubletake","head_eyeroll","head_cheer","head_pout"]:
			var tex = Art.get_texture(hero.id,key)
			if tex == null or tex.get_width() <= 0:
				push_error("Packed hero texture missing: "+hero.id+"/"+key); quit(1); return
			count += 1
	var main = Main.instantiate(); main.settings.values.sound = false; root.add_child(main)
	main.set_process(false); main.set_view_size(Vector2(390,844)); main.request_game("computer")
	main._confirm_hero("ryan_blaze","Pack Check")
	if main.cinematic.kind != "versus": push_error("Packed select/versus flow failed"); quit(1); return
	main.cinematic.advance(2.81)
	main.game.status = 2; main._show_spotlight(); main.cinematic.advance(5.1)
	if not main.controls.has_all(["again","menu"]) or main.cinematic.hero.art_key != "victory":
		push_error("Packed winner flow failed"); quit(1); return
	main.go_home(); main.queue_free(); await process_frame
	print("NINEWEAVE_PACK PASS hero_textures=",count," select/versus/winner=PASS")
	quit()

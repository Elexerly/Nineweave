extends RefCounted
## Thin adapter into the normal computer-match/hero-cinematic flow.
const Session = preload("res://tournament/session.gd")
const Screen = preload("res://tournament/screen.gd")
const Roster = preload("res://characters/roster.gd")
var main
var session
var screen
var match_active: bool = false
var starting: bool = false
var recorded: bool = false
var match_level: String = "Easy"
var pending_events: Array = []
var video_seen: bool = false
func setup(host):
	main = host
	# Deriving from the profile path keeps harness profiles isolated too.
	if session == null: session = Session.new(main.profile.path.get_basename()+"-tournament.cfg")
	if main.page == "title" and not session.active.is_empty(): main.page = "tournament"
func request():
	if not session.active.is_empty(): show(); return
	main._pending_game = {"mode":"tournament","mark":1}; main._select_player = 0
	main.open_character_select()
func create(hero: String, seed_value: int = -1):
	session.create(hero,seed_value); pending_events = []; video_seen = false; show()
func show():
	if session.active.is_empty(): main.go_home(); return
	main._leave_online(); main.thinking = false; main.hint_busy = false; match_active = false
	main.cinematic.clear(); main.board.clear_effects(); main.callout.callout = ""
	main.page = "tournament"; main.overlay = ""; main._rebuild()
func build(size: Vector2):
	screen = Screen.new(); screen.size = size; screen.data = session.active.duplicate(true)
	screen.events = pending_events; screen.reduced_motion = bool(main.settings.values.reduced_motion)
	screen.trophies = session.total_trophies(); screen.hero_trophies = int(session.wins.get(session.active.hero,0))
	screen.video_source = main.hero_video; screen.play_victory = not video_seen; screen.sound_enabled = main.sound.enabled
	screen.victory_started.connect(func(): video_seen = true)
	screen.action.connect(_action)
	main.add_child(screen); main.ui_nodes.append(screen); main.controls.merge(screen.controls)
	screen.video_overlay.audio_active.connect(main.sound.set_hero_video_audio)
func play(ad_checked: bool = false):
	if not ad_checked:
		main.match_ads.before_next(func(): play(true)); return
	if session.current().is_empty() or match_active: return
	if is_instance_valid(screen) and is_instance_valid(screen.bracket) and not screen.bracket.settled(): return
	main.profile.choose(str(session.active.hero),str(main.profile.data.display_name))
	main.rival_character = session.opponent(); match_level = session.level()
	match_active = true; recorded = false; pending_events = []; starting = true
	main.start_game("computer",1,true,true)
	starting = false
func capture_result(status: int):
	if not match_active or recorded or not status in [1,2]: return
	recorded = session.finish(status == main.human_mark)
	if recorded: pending_events = session.last_events.duplicate(true)
func after_match():
	capture_result(main.game.status)
	if main.game.status == 3:
		match_active = false; play(); return
	show()
func _action(kind: String):
	main.sound.cue("ui")
	match kind:
		"play": play()
		"retry": create(str(session.active.hero))
		"abandon": session.abandon(); pending_events = []; main.go_home()
		"menu":
			if session.active.get("status","") in ["champion","eliminated"]: session.abandon()
			pending_events = []; main.go_home()

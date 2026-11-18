extends SceneTree
const R = preload("res://characters/roster.gd")
const Profile = preload("res://characters/profile.gd")
const Art = preload("res://characters/art.gd")
const Video = preload("res://characters/hero_video.gd")
const Audio = preload("res://characters/hero_audio.gd")
const Overlay = preload("res://characters/hero_video_overlay.gd")
const Main = preload("res://main/main.tscn")
const Store = preload("res://settings/store.gd")
const DeviceStore = preload("res://net/device_store.gd")
const Transport = preload("res://net/net_transport.gd")
const Fake = preload("res://tests/fake_http.gd")
var checks = 0
var failures = 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	ok(R.DATA.size() == 35 and R.selectable_indices().size() == 32,"public roster count unchanged")
	ok(R.DATA[12].id == "jb_circuit" and R.get_hero("jb_circuit").name == "James II","tech ranger occupies Professor slot")
	ok(R.valid("professor_gilt") and R.canonical_id("professor_gilt") == "professor_gilt","Professor canonical ID preserved")
	ok(not R.selectable("professor_gilt") and R.selectable("professor_gilt",["professor_gilt"]),"Professor is a hidden account unlock")
	ok(R.selectable_indices(["professor_gilt","nick","professor_gilt","fake"]).size() == 34,"both secret heroes remain unique")
	ok(R.selectable("nick",["nick"]) and not R.selectable("nick"),"Nick entitlement unchanged")
	ok(R.get_hero("shard_jack").name == "Jack Sovereign","Jack Sovereign remains a separate character")
	ok(R.audio_index("professor_gilt") == 10 and R.audio_index("jb_circuit") == 10,"stable original audio motif")
	var original = R.get_hero("james_ii")
	ok(original.id == "james_ii" and original.name == "Sevryn","old James II renamed without changing canonical ID")
	ok(R.canonical_id("james_ii") != R.canonical_id("jb_circuit"),"old and new identities never alias")
	ok(R.tile_label("james_ii") == "SEVRYN" and R.tile_label("jb_circuit") == "JAMES II","display names assigned to the correct two identities")
	ok(R.tile_lines("james_ii") == PackedStringArray(["SEVRYN"]) and R.tile_lines("jb_circuit") == PackedStringArray(["JAMES","II"]),"both tile captions use correct names")
	ok(original.concept == "Royal battle-mage · purple coat, silver staff, airborne homework" and original.palette == ["9b6bff","2c1e55","e8e4ff"] and original.mark == "royal_rune" and original.prop == "staff_book","old hero design metadata retained")
	ok(original.pop == "Second to none." and original.victory == "By royal decree: one more game!" and R.audio_index("james_ii") == 10,"old hero copy and audio motif retained")
	var legacy_path = "user://sevryn-legacy-profile.cfg"
	var legacy = ConfigFile.new(); legacy.set_value("profile","character_id","james_ii"); legacy.save(legacy_path)
	var restored = Profile.new(legacy_path)
	ok(restored.data.character_id == "james_ii" and R.get_hero(restored.data.character_id).name == "Sevryn","old save resolves Sevryn rather than the tech ranger")
	restored.save(); ok(Profile.new(legacy_path).data.character_id == "james_ii","old save ID survives roundtrip")
	var old_net = Transport.new(); old_net.character_id = "james_ii"; old_net.seat = 1
	ok(old_net.character_payload().character_id == "james_ii","old outgoing online reference retained")
	ok(old_net.receive_characters({"1":"jb_circuit","2":"james_ii"}) and old_net.remote_character_id == "james_ii","old incoming online reference retained")
	old_net.free()
	var path = "user://jb-professor-legacy.cfg"
	var config = ConfigFile.new(); config.set_value("profile","character_id","professor_gilt"); config.save(path)
	var profile = Profile.new(path)
	ok(profile.data.character_id == "professor_gilt","old Professor saves still resolve")
	profile.save(); ok(Profile.new(path).data.character_id == "professor_gilt","old ID survives save roundtrip")
	for key in ["splash","versus","victory","head_neutral","head_smug","head_panic","head_doubletake","head_eyeroll","head_cheer","head_pout"]:
		var old_texture = Art.get_texture("james_ii",key)
		ok(old_texture != null and old_texture.resource_path == "res://assets/heroes/james_ii/"+key+".webp","old artwork remains on canonical path "+key)
		var texture = Art.get_texture("jb_circuit",key)
		ok(texture != null,"new art loads "+key)
		if texture == null: continue
		var image = texture.get_image()
		ok(image.detect_alpha() != Image.ALPHA_NONE,"real alpha "+key)
		ok(image.get_size() == Vector2i(256,256) if key.begins_with("head_") else image.get_height() == 768,"pipeline dimensions "+key)
	var video = Video.new(); root.add_child(video)
	for old_kind in ["intro","victory"]:
		ok(video.local_path("james_ii",old_kind) == "res://assets/hero_video/james_ii/"+old_kind+".ogv","old video remains on canonical path "+old_kind)
	for kind in ["intro","victory"]:
		ok(video.has_clip("jb_circuit",kind) and video.is_ready("jb_circuit",kind),"bundled media ready "+kind)
		var stream = Audio.load_clip(video.local_path("jb_circuit",kind))
		ok(stream != null and stream.get_length() >= 5.99 and stream.get_length() <= 6.05,"independent Vorbis audio decodes "+kind)
	ok(Overlay.INTRO_PLAY_SECONDS == 6.0 and Overlay.INTRO_FADE_SECONDS == .3,"six seconds after prelude with existing fade")
	ok(is_equal_approx(Overlay.soundtrack_tail_gain("jb_circuit","intro",5.85,6.0),.5),"intro fades in final 0.3 seconds")
	ok(Overlay.soundtrack_tail_gain("jb_circuit","victory",5.9,6.04) == 1.0,"victory audio timing unchanged")
	var ui = Main.instantiate(); ui.test_online_bypass = true
	ui.settings = Store.new("user://jb-settings.cfg"); ui.settings.values.sound = false
	ui.profile = Profile.new("user://jb-profile.cfg"); ui.profile.data.onboarded = true
	ui.account.store = DeviceStore.new("user://jb-device.cfg")
	var fake = Fake.new(); ui.account.api.request_factory = func(): return fake
	root.add_child(ui); await process_frame; await process_frame
	ui.account.api.cancel_all()
	ui.account.store.accept_consent("Tester",DeviceStore.consent_payload()); ui.account.store.keep_device("nwd_professor","Tester"); ui.account.store.data.signed_out = false
	for code in ["Prof26","pRoF26"]:
		ui.overlay = "secret_codes"; ui._rebuild(); ui._redeem_code(code)
		ok(fake.requests.back().body == {"code":code},"mixed-case code sent to authoritative server "+code)
		fake.respond(200,{"unlocked_backgrounds":[],"unlocked_heroes":["professor_gilt","nick"],"unlock":{"kind":"hero","id":"professor_gilt"}})
		ok("Professor Gilt" in ui._code_message and "nick" in ui.settings.values.unlocked_heroes,"grant keeps Nick and confirms Professor "+code)
	ui.page = "character_select"; ui._rebuild()
	ok(ui.hero_select.portraits.size() == 34,"owned Professor and Nick available")
	ui.hero_select.focus_hero("professor_gilt"); ok(ui.hero_select.selected_id == "professor_gilt","owned Professor selectable")
	ui.profile.data.character_id = "professor_gilt"
	ui._account_player({"unlocked_heroes":[],"last_hero_id":"professor_gilt"}); ui._rebuild()
	ok(ui.hero_select.portraits.size() == 32 and ui.profile.data.character_id != "professor_gilt","account switch removes unowned Professor")
	ui._account_player({"unlocked_heroes":["professor_gilt","nick"],"last_hero_id":"professor_gilt"}); ui._rebuild()
	ok(ui.settings.values.unlocked_heroes == ["professor_gilt","nick"],"server profile restores permanent account inventory")
	ui._hero_changed = false
	ui._account_player({"unlocked_heroes":[],"last_hero_id":"james_ii"})
	ok(ui.profile.data.character_id == "james_ii" and R.get_hero(ui.profile.data.character_id).name == "Sevryn","server last hero preserves old identity after rename")
	ui._account_player({"unlocked_heroes":[],"last_hero_id":"jb_circuit"})
	ok(ui.profile.data.character_id == "jb_circuit" and R.get_hero(ui.profile.data.character_id).name == "James II","new tech identity remains independently selectable")
	ui.settings.save(); ok(Store.new("user://jb-settings.cfg").values.unlocked_heroes.is_empty(),"local settings cannot forge ownership")
	ui.queue_free(); video.queue_free(); await process_frame
	print("NINEWEAVE_JB_CIRCUIT ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(1 if failures else 0)

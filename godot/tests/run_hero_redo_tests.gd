extends SceneTree
const R = preload("res://characters/roster.gd")
const Profile = preload("res://characters/profile.gd")
const Art = preload("res://characters/art.gd")
const Video = preload("res://characters/hero_video.gd")
const Audio = preload("res://characters/hero_audio.gd")
const Transport = preload("res://net/net_transport.gd")
const Rig = preload("res://characters/rig.gd")
var failures = 0
var checks = 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	var hero = R.get_hero("patrick_laquin")
	ok(R.selectable_indices().size() == 32 and R.DATA[11].id == hero.id,"same roster slot, 32 heroes")
	ok(hero.name == "Patrick Laquin" and hero.palette == ["1c1c20","6b6f78","e0a040"],"name and palette")
	ok(hero.concept == "Bounty hunter · wrist-crossbow and chain bola" and hero.mark == "crosshair" and hero.body == "athletic" and hero.prop == "crossbow","concept and rig metadata")
	ok(hero.pop == "Your bounty just went up." and hero.victory == "Collected. Nine boards, one bounty." and hero.defeat == "He tears up his own wanted poster." and hero.action == "BAGGED!","approved copy")
	ok(R.canonical_id("kite_hollow") == hero.id and R.get_hero("kite_hollow") == hero,"old record alias")
	ok(R.audio_index(hero.id) == 9 and R.audio_index("kite_hollow") == 9,"legacy stinger retained")
	var cfg = ConfigFile.new(); var path = "user://hero-redo-legacy.cfg"
	cfg.set_value("profile","character_id","kite_hollow"); cfg.save(path)
	var profile = Profile.new(path)
	ok(profile.data.character_id == hero.id,"old save migrates to Patrick")
	profile.save(); ok(Profile.new(path).data.character_id == hero.id,"migration persists")
	ok(not DirAccess.dir_exists_absolute("res://assets/heroes/kite_hollow") and not DirAccess.dir_exists_absolute("res://assets/hero_video/kite_hollow"),"retired assets removed")
	for key in ["versus","victory","splash","head_neutral","head_smug","head_panic","head_doubletake","head_eyeroll","head_cheer","head_pout"]:
		var texture = Art.get_texture(hero.id,key)
		ok(texture != null and Art.get_texture("kite_hollow",key) == texture,"legacy art resolves "+key)
		var image = texture.get_image()
		ok(image != null and image.detect_alpha() != Image.ALPHA_NONE,"transparent art "+key)
		ok(image.get_size() == Vector2i(256,256) if key.begins_with("head_") else image.get_height() == 768,"matching art dimensions "+key)
	var video = Video.new(); root.add_child(video)
	for kind in ["intro","victory"]:
		ok(video.has_clip("kite_hollow",kind) and video.is_ready(hero.id,kind),"old video ID resolves "+kind)
		ok(Video.relative_path("kite_hollow",kind) == "hero_video/patrick_laquin/"+kind+".ogv","canonical media path "+kind)
		ok(Audio.load_clip(video.local_path(hero.id,kind)) != null,"Patrick separate audio decodes "+kind)
	for key in Video.MEDIA_REVISIONS:
		var parts = key.split("/")
		var stream = Audio.load_clip(video.local_path(parts[0],parts[1]))
		ok(stream != null and stream.get_length() > 0.0,"replacement separate audio decodes "+key)
		ok(Video.versioned_relative_path("hero_video/"+key+".ogv").ends_with("?v="+Video.MEDIA_REVISIONS[key]),"cache bust "+key)
	ok(Video.MEDIA_REVISIONS["kellen_byte/intro"] == "60713ca" and Video.MEDIA_REVISIONS["professor_gilt/intro"] == "fd1c7e0","previous trims preserved")
	var transport = Transport.new(); transport.character_id = "kite_hollow"; transport.seat = 1
	ok(transport.character_payload().character_id == hero.id,"old outgoing online character canonicalized")
	ok(transport.receive_characters({"1":"nyx_thread","2":"kite_hollow"}) and transport.remote_character_id == hero.id,"old incoming online character canonicalized")
	transport.free()
	var rig = Rig.new(); rig.configure("kite_hollow"); root.add_child(rig)
	ok(rig.hero_id == hero.id and rig.bones.has("prop"),"old rig ID resolves bounty hunter")
	rig.pose(.1); rig.queue_free(); video.free()
	await process_frame
	print("NINEWEAVE_HERO_REDO ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

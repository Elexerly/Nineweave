extends SceneTree
const R = preload("res://characters/roster.gd")
const Art = preload("res://characters/art.gd")
const Audio = preload("res://characters/hero_audio.gd")
const Main = preload("res://main/main.tscn")
const Store = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Fake = preload("res://tests/fake_http.gd")
var checks = 0
var failures = 0
func ok(value: bool,label: String):
 checks += 1
 if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
 ok(R.DATA.size() == 35 and R.selectable_indices().size() == 32,"32 standard and three hidden heroes")
 ok(not R.selectable("jb_rocker") and R.selectable("jb_rocker",["jb_rocker"]),"JB requires server inventory")
 ok(R.selectable_indices(["nick","professor_gilt","jb_rocker"]).size() == 35,"all three secret heroes available once unlocked")
 for key in ["versus","victory","splash","head_neutral","head_smug","head_cheer","head_pout","head_panic","head_eyeroll","head_doubletake"]:
  var tex = Art.get_texture("jb_rocker",key)
  ok(tex != null,"art loads "+key)
  if tex:
   ok(tex.get_image().detect_alpha() != Image.ALPHA_NONE,"alpha "+key)
   ok(tex.get_height() == (256 if key.begins_with("head_") else 768),"runtime size "+key)
 for kind in ["intro","victory"]:
  var stream = Audio.load_clip("res://assets/hero_video/jb_rocker/"+kind+".ogv")
  ok(stream != null and absf(stream.get_length()-6.0)<.05,"separated six-second soundtrack "+kind)
 var ui = Main.instantiate(); ui.test_online_bypass = true
 ui.settings = Store.new("user://lexerly-qa-settings.cfg"); ui.settings.values.sound = false
 ui.profile = Profile.new("user://lexerly-qa-profile.cfg"); ui.profile.data.onboarded = true
 ui.account.api.request_factory = func(): return Fake.new()
 root.add_child(ui); await process_frame; await process_frame
 ui.account.api.cancel_all()
 ok(ui.title_label.text == "LEXERLY","new title label")
 ok(ui.title_label.material is ShaderMaterial,"original gold shimmer material")
 var announcement = load("res://assets/audio/announcer/nineweave.ogg")
 ok(announcement != null and announcement.get_length()>6.5,"complete Lexerly recording and flourish")
 ui.queue_free(); await process_frame
 print("LEXERLY PASS" if failures == 0 else "LEXERLY FAIL"," checks=",checks," failures=",failures)
 quit(0 if failures == 0 else 1)

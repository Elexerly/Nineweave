extends SceneTree
## Offline native source checks. Never sends requests or touches Apple/Neon.
const Video = preload("res://characters/hero_video.gd")
const Api = preload("res://net/json_api.gd")
const Roster = preload("res://characters/roster.gd")
var checks = 0
var failures = 0
func ok(condition: bool, label: String):
	checks += 1
	if not condition: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	var cfg = ConfigFile.new()
	ok(cfg.load("res://export_presets.cfg") == OK,"export config readable")
	ok(cfg.get_value("preset.0","platform") == "Web","web remains first preset")
	ok("assets/hero_video/**/*.ogv" in str(cfg.get_value("preset.0","exclude_filter")),"web keeps sidecar policy")
	ok(cfg.get_value("preset.1","platform") == "iOS","iOS preset")
	ok("assets/hero_video/**/*.ogv" in str(cfg.get_value("preset.1","include_filter")),"native clip inclusion")
	ok(not "assets/hero_video/**/*.ogv" in str(cfg.get_value("preset.1","exclude_filter")),"native clips not excluded")
	ok(cfg.get_value("preset.1.options","application/targeted_device_family") == 2,"iPhone + iPad")
	ok(cfg.get_value("preset.1.options","application/export_project_only"),"no automatic archive")
	ok(Api.request_url("", "/auth/device") == "https://nineweave.grok.me/api/nineweave/auth/device","native account URL is absolute")
	var video = Video.new(); root.add_child(video)
	ok(video.bundled() and not video.streaming(),"native bundled media")
	ok(not video.cache.is_inside_tree(),"native does not start media downloader")
	var count = 0
	for hero in Roster.DATA:
		for kind in ["intro","victory"]:
			ok(video.is_ready(hero.id,kind),"native clip ready "+hero.id+"/"+kind)
			ok(video.local_path(hero.id,kind).begins_with("res://"),"native resource path")
			count += 1
	ok(count == 70,"all 32 default hero pairs plus Nick, Professor and JB pairs")
	ok(video.local_path("kite_hollow","intro") == video.local_path("patrick_laquin","intro"),"legacy native save resolves Patrick")
	video.free()
	print("NINEWEAVE_NATIVE_READINESS ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

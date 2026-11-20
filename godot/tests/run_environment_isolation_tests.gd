extends SceneTree
## Invocation can use editor source or --main-pack for each iOS pack. No live requests.
const Env = preload("res://net/game_environment.gd")
const API = preload("res://net/json_api.gd")
const HTTP = preload("res://net/http_polling_transport.gd")
const Device = preload("res://net/device_store.gd")
const Profile = preload("res://characters/profile.gd")
const Settings = preload("res://settings/store.gd")
const Session = preload("res://tournament/session.gd")
const Cache = preload("res://characters/hero_video_cache.gd")
const Main = preload("res://main/main.tscn")
var checks := 0
var failures := 0
func check(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	var staged := "--expect-staging" in OS.get_cmdline_user_args()
	var expected_origin := Env.STAGING_ORIGIN if staged else Env.LIVE_ORIGIN
	var prefix := "user://lexerly-staging-" if staged else "user://"
	check(Env.staging() == staged,"only dedicated staging export opts in")
	check(Env.origin() == expected_origin,"build pins intended environment")
	check(API.request_url("", "/health") == expected_origin+"/api/nineweave/health","default/invalid URL fails into same environment")
	check(API.request_url(Env.LIVE_ORIGIN,"/me") == expected_origin+"/api/nineweave/me","live override cannot escape staging build")
	if staged: check(API.request_url("http://127.0.0.1:5432","/me").begins_with(Env.STAGING_ORIGIN+"/"),"local override cannot escape pinned staging")
	var api = API.new(); root.add_child(api)
	check(api.base_url == expected_origin,"account JSON client defaults to intended host")
	if staged: check(api._request.max_redirects == 0,"staging rejects cross-origin redirects")
	var room = HTTP.new(); root.add_child(room)
	check(room.base_url == expected_origin and room.api.base_url == expected_origin and room.aux_api.base_url == expected_origin,"room, poll, and aux requests use same environment")
	var cache := Cache.new()
	check(cache.root_path == prefix+"hero_video","staging assets use distinct cache namespace")
	check(Env.save_path("nineweave-device.cfg") == prefix+"nineweave-device.cfg","device credential path scope")
	check(Env.save_path("nineweave-profile.cfg") == prefix+"nineweave-profile.cfg","profile path scope")
	check(Env.save_path("nineweave.cfg") == prefix+"nineweave.cfg","settings and resume path scope")
	check(Env.save_path("nineweave-tournament.cfg") == prefix+"nineweave-tournament.cfg","standalone tournament save path scope")
	var fixture_path := "user://isolated-environment-fixture.cfg"
	check(Device.new(fixture_path).path == fixture_path and Profile.new(fixture_path).path == fixture_path and Settings.new(fixture_path).path == fixture_path and Session.new(fixture_path).path == fixture_path,"explicit fixture paths remain unchanged")
	var ui = Main.instantiate()
	ui.test_online_bypass = true
	ui.settings = Settings.new(fixture_path); ui.settings.values.tutorial_completed = true
	ui.profile = Profile.new(fixture_path)
	ui.account.store = Device.new(fixture_path)
	root.add_child(ui); ui.set_process(false)
	ui.set_view_size(Vector2(390,844))
	# The default test-only account bypass and empty fixture prevent live calls.
	var badge := ui.get_node_or_null("TestServerBadge")
	check(is_instance_valid(badge) == staged,"test server badge is only present in the explicit staging build")
	if staged:
		check(badge.text == "TEST SERVER" and badge.mouse_filter == Control.MOUSE_FILTER_IGNORE,"test badge is clear and never intercepts taps")
	cache.free(); ui.free(); room.free(); api.free()
	print("LEXERLY_ENVIRONMENT_ISOLATION staging=",staged," checks=",checks," failures=",failures)
	quit(1 if failures else 0)

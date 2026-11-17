extends Node
## Poing v5.1.0 native singleton contract. Test IDs ONLY, no desktop mock or live IDs.
## Optional native binaries are deliberately not installed/enabled by this source.
const IOS_TEST_UNIT = "ca-app-pub-3940256099942544/4411468910"
const ANDROID_TEST_UNIT = "ca-app-pub-3940256099942544/1033173712"
signal completed
var _mobile
var _ads
var _uid: int = -1
var _initialized = false
var _loading = false
var _loaded = false
var _presenting = false
var _consent = false
var _platform = ""
func start(consent_allowed: bool) -> bool:
	if not consent_allowed or OS.get_name() not in ["iOS","Android"]: return false
	if _mobile != null:
		_consent = true; preload_ad(); return true
	if not Engine.has_singleton("PoingGodotAdMob") or not Engine.has_singleton("PoingGodotAdMobInterstitialAd"): return false
	return attach_plugins(Engine.get_singleton("PoingGodotAdMob"),Engine.get_singleton("PoingGodotAdMobInterstitialAd"),OS.get_name(),consent_allowed)
func attach_plugins(mobile, ads, platform: String, consent_allowed: bool) -> bool:
	# Injectable native boundary for offline tests. Never manufactures an ad or purchase.
	if _mobile != null or not consent_allowed or platform not in ["iOS","Android"]: return false
	if not is_instance_valid(mobile) or not is_instance_valid(ads): return false
	if not mobile.has_method("initialize") or not mobile.has_signal("on_initialization_complete"): return false
	for method in ["create","load","show","destroy"]:
		if not ads.has_method(method): return false
	for event in ["on_interstitial_ad_loaded","on_interstitial_ad_failed_to_load","on_interstitial_ad_dismissed_full_screen_content","on_interstitial_ad_failed_to_show_full_screen_content"]:
		if not ads.has_signal(event): return false
	_mobile = mobile; _ads = ads; _consent = true; _platform = platform
	_mobile.on_initialization_complete.connect(_initialized_callback,CONNECT_DEFERRED)
	_ads.on_interstitial_ad_loaded.connect(_loaded_callback,CONNECT_DEFERRED)
	_ads.on_interstitial_ad_failed_to_load.connect(_load_failed,CONNECT_DEFERRED)
	_ads.on_interstitial_ad_dismissed_full_screen_content.connect(_dismissed,CONNECT_DEFERRED)
	_ads.on_interstitial_ad_failed_to_show_full_screen_content.connect(_show_failed,CONNECT_DEFERRED)
	_mobile.initialize()
	return true
func _initialized_callback(_status: Dictionary):
	_initialized = true; preload_ad()
func preload_ad():
	if not _initialized or not _consent or _loading or _loaded or _presenting: return
	_uid = _ads.create(); _loading = true
	_ads.load(IOS_TEST_UNIT if _platform == "iOS" else ANDROID_TEST_UNIT,{"extras":{"npa":"1"},"mediation_extras":{},"google_request_agent":"Nineweave-test-Poing-5.1.0"},PackedStringArray(),_uid)
func _loaded_callback(uid: int):
	if uid != _uid: return
	_loading = false
	if not _consent: _destroy(); return
	_loaded = true
func _load_failed(uid: int, _error: Dictionary):
	if uid != _uid: return
	_loading = false; _destroy()
func is_ready() -> bool: return _consent and _loaded and not _presenting
func show_interstitial() -> bool:
	if not is_ready(): return false
	_loaded = false; _presenting = true
	_ads.show(_uid)
	return true
func _dismissed(uid: int):
	if uid != _uid or not _presenting: return
	_presenting = false; _destroy(); completed.emit()
func _show_failed(uid: int, _error: Dictionary): _dismissed(uid)
func revoke_consent():
	_consent = false
	# Never pretend a visible native view closed; wait for its dismissal callback.
	if not _presenting: _destroy()
func _destroy():
	if _uid >= 0 and _ads != null: _ads.destroy(_uid)
	_uid = -1; _loading = false; _loaded = false
func _exit_tree(): _destroy()

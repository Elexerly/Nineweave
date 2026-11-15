extends Node
const API = preload("res://net/json_api.gd")
const Store = preload("res://net/device_store.gd")
const Roster = preload("res://characters/roster.gd")
signal player_received(player: Dictionary)
signal onboarding_complete
signal name_updated(screen_name: String)
signal email_changed(email: String, verification_status: String)
signal error(message: String)
var store = Store.new()
var api = API.new()
var busy: bool = false
var _name_draft: String = ""
var _consent: Dictionary = {}
var _rename: String = ""
## Local-only boundary until PATCH /me explicitly supports email. Never probe by
## sending personal data to an older API. Future verification belongs here.
func save_email(value: String) -> bool:
	if not store.keep_email(value):
		error.emit("Enter a valid email, such as name@example.com."); return false
	email_changed.emit(store.data.email,store.data.email_status)
	return true
func continue_without_email():
	store.skip_email()
func _ready():
	api.completed.connect(_completed); add_child(api)
func refresh():
	if not str(store.data.device_token).is_empty(): api.submit("/me",HTTPClient.METHOD_GET,{},"me",store.data.device_token)
func create_screen_name(value: String):
	if busy: return
	var clean = value.strip_edges()
	if clean.is_empty() or clean.length() > 24:
		error.emit("Choose a screen name with 1–24 characters."); return
	_name_draft = clean; _consent = Store.consent_payload(); busy = true
	# Register with name only so current production (no consent columns yet) still works.
	# Consent is recorded on the following PATCH /me, or kept locally if that API is older.
	if str(store.data.device_token).is_empty():
		api.submit("/auth/device",HTTPClient.METHOD_POST,{"screen_name":clean},"register")
	else: _patch_consent()
func _patch_consent():
	var body = _consent.duplicate(); body.screen_name = _name_draft
	api.submit("/me",HTTPClient.METHOD_PATCH,body,"consent",store.data.device_token)
func rename(value: String):
	if busy or not _rename.is_empty(): return
	var clean = value.strip_edges()
	if clean.is_empty() or clean.length() > 24: error.emit("Choose a screen name with 1–24 characters."); return
	_rename = clean
	api.submit("/me",HTTPClient.METHOD_PATCH,{"screen_name":clean},"rename",store.data.device_token)
func choose_hero(id: String):
	if not Roster.valid(id) or str(store.data.device_token).is_empty(): return
	api.submit("/me",HTTPClient.METHOD_PATCH,{"last_hero_id":Roster.canonical_id(id)},"hero",store.data.device_token)
func _completed(operation: String, _response: int, data: Dictionary, problem: String):
	if not problem.is_empty():
		if operation == "consent" and _legacy_consent_api(problem):
			store.accept_consent(str(_name_draft),_consent)
			busy = false; name_updated.emit(store.data.screen_name); onboarding_complete.emit()
			return
		if operation in ["register","consent"]: busy = false
		if operation == "rename": _rename = ""
		error.emit(problem); return
	var player = data.get("player",data)
	if not player is Dictionary: error.emit("Online server not available. Invalid player response."); busy = false; return
	match operation:
		"register":
			if not store.keep_device(str(data.get("token","")),_name_draft):
				busy = false; error.emit("Online server not available. Account could not be saved."); return
			_patch_consent()
		"consent":
			store.accept_consent(str(player.get("screen_name",_name_draft)),_consent)
			busy = false; name_updated.emit(store.data.screen_name); onboarding_complete.emit()
		"rename":
			store.data.screen_name = str(player.get("screen_name",_rename)); store.save()
			_rename = ""; name_updated.emit(store.data.screen_name)
		"me":
			if player.get("screen_name") is String and not player.screen_name.is_empty():
				store.data.screen_name = player.screen_name; store.save(); name_updated.emit(player.screen_name)
			player_received.emit(player)

func _legacy_consent_api(problem: String) -> bool:
	var text = problem.to_lower()
	if not "unknown field" in text: return false
	for field in ["tos_version","privacy_version","accepted_at","age_confirmed"]:
		if field in text: return true
	return false

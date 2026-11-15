extends Node
const API = preload("res://net/json_api.gd")
const Store = preload("res://net/device_store.gd")
const Roster = preload("res://characters/roster.gd")
signal player_received(player: Dictionary)
signal onboarding_complete
signal sync_finished
signal name_updated(screen_name: String)
signal email_changed(email: String, verification_status: String)
signal error(message: String)
var store = Store.new()
var api = API.new()
var busy: bool = false
var _name_draft: String = ""
var _consent: Dictionary = {}
var _rename: String = ""
var _syncing: bool = false
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
	if store.complete() and (store.data.pending_sync or not store.has_device_token()): sync_pending()
	elif store.has_device_token(): api.submit("/me",HTTPClient.METHOD_GET,{},"me",store.data.device_token)
func sync_pending():
	if busy or not store.complete() or store.online_ready(): return
	store.data.pending_sync = true; store.save()
	_name_draft = store.data.screen_name; _consent = {}
	for key in ["tos_version","privacy_version","accepted_at","age_confirmed"]: _consent[key] = store.data[key]
	_syncing = true; busy = true
	_submit_registration()
func create_screen_name(value: String):
	if busy: return
	var clean = value.strip_edges()
	if not Store.valid_screen_name(clean):
		error.emit("Choose a screen name with 1–24 characters."); return
	_name_draft = clean; _consent = Store.consent_payload(); busy = true; _syncing = false
	_submit_registration()
func _submit_registration():
	# Register with name only so current production (no consent columns yet) still works.
	# Consent is recorded on the following PATCH /me, or kept locally if that API is older.
	if not store.has_device_token():
		api.submit("/auth/device",HTTPClient.METHOD_POST,{"screen_name":_name_draft},"register")
	else: _patch_consent()
func _patch_consent():
	var body = _consent.duplicate(); body.screen_name = _name_draft
	api.submit("/me",HTTPClient.METHOD_PATCH,body,"consent",store.data.device_token)
func rename(value: String):
	if busy or not _rename.is_empty(): return
	var clean = value.strip_edges()
	if not Store.valid_screen_name(clean): error.emit("Choose a screen name with 1–24 characters."); return
	if not store.online_ready():
		if not store.complete(): return
		store.data.screen_name = clean; store.data.pending_sync = true; store.save()
		name_updated.emit(clean); return
	_rename = clean
	api.submit("/me",HTTPClient.METHOD_PATCH,{"screen_name":clean},"rename",store.data.device_token)
func choose_hero(id: String):
	if not Roster.valid(id) or not store.online_ready(): return
	api.submit("/me",HTTPClient.METHOD_PATCH,{"last_hero_id":Roster.canonical_id(id)},"hero",store.data.device_token)
func _completed(operation: String, response: int, data: Dictionary, problem: String):
	if not problem.is_empty():
		if operation in ["register","consent"]:
			if operation == "consent" and response == 400 and _legacy_consent_api(problem):
				_finish_registration(false); return
			if _is_outage(response,problem):
				# A chosen name and the actual consent are enough for local play. No
				# substitute credential is created; live rooms wait for registration.
				_finish_registration(true); return
			busy = false
			if _syncing:
				# A reachable server rejected an offline name. Resolve it on the
				# name screen, including after restart, without discarding consent.
				store.data.registration_rejected = true; store.save(); _syncing = false
				error.emit(problem); sync_finished.emit(); return
		if operation == "rename": _rename = ""
		error.emit(problem); return
	var player = data.get("player",data)
	if not player is Dictionary:
		if operation in ["register","consent"]: _finish_registration(true)
		else: error.emit("Online server not available. Invalid player response.")
		return
	match operation:
		"register":
			if not store.keep_device(str(data.get("token","")),_name_draft):
				_finish_registration(true); return
			_patch_consent()
		"consent":
			_finish_registration(false,str(player.get("screen_name",_name_draft)))
		"rename":
			store.data.screen_name = str(player.get("screen_name",_rename)); store.save()
			_rename = ""; name_updated.emit(store.data.screen_name)
		"me":
			if player.get("screen_name") is String and Store.valid_screen_name(player.screen_name):
				store.data.screen_name = player.screen_name; store.save(); name_updated.emit(player.screen_name)
			player_received.emit(player)

func _finish_registration(pending: bool, confirmed_name: String = ""):
	store.data.pending_sync = pending; store.data.registration_rejected = false
	store.accept_consent(confirmed_name if Store.valid_screen_name(confirmed_name) else _name_draft,_consent)
	busy = false
	var was_syncing = _syncing; _syncing = false
	name_updated.emit(store.data.screen_name)
	if was_syncing: sync_finished.emit()
	else: onboarding_complete.emit()

func _is_outage(response: int, problem: String) -> bool:
	# Never turn a reachable server's validation/name conflict into acceptance,
	# even when a proxy or fallback error contains generic availability wording.
	if response >= 400 and response < 500: return response == 408
	if response == 0 or response >= 500: return true
	var text = problem.to_lower()
	return "not available" in text or "can't reach" in text or "cannot reach" in text or "timeout" in text

func _legacy_consent_api(problem: String) -> bool:
	var text = problem.to_lower()
	if not "unknown field" in text: return false
	for field in ["tos_version","privacy_version","accepted_at","age_confirmed"]:
		if field in text: return true
	return false

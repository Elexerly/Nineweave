extends Node
const API = preload("res://net/json_api.gd")
const Store = preload("res://net/device_store.gd")
const Roster = preload("res://characters/roster.gd")
signal player_received(player: Dictionary)
signal onboarding_complete
signal sync_finished
signal name_updated(screen_name: String)
signal email_changed(email: String, verification_status: String)
signal email_flow_changed
signal error(message: String)
var store = Store.new()
var api = API.new()
var busy: bool = false
var _name_draft: String = ""
var _consent: Dictionary = {}
var _rename: String = ""
var _syncing: bool = false
var _refreshing: bool = false
var _recovering_device: bool = false
var _account_unavailable: bool = false
## Session-only capability: neither a saved address nor config can enable writes.
var email_capable: bool = false
var email_capability_known: bool = false
var email_busy: bool = false
var email_pending: bool = false
var email_challenge: Dictionary = {}
var email_retry_until: float = 0.0
var email_message: String = ""
var _email_needs_store: bool = false
const EMAIL_SETUP_TIMEOUT = 25.0
var _email_waiting_for_account: bool = false
var _email_setup_elapsed: float = 0.0
var _email_recovery_attempted: bool = false
func email_online_enabled() -> bool:
	return email_capable and store.online_ready()
func save_email(value: String) -> bool:
	if email_busy: return false
	if not store.keep_email(value):
		error.emit("Enter a valid email, such as name@example.com."); return false
	email_changed.emit(store.data.email,store.data.email_status)
	email_challenge = {}; email_pending = false; _email_needs_store = true
	_email_recovery_attempted = false
	_email_waiting_for_account = true; _email_setup_elapsed = 0.0
	email_busy = true; email_message = "Setting up your account…"
	email_flow_changed.emit()
	_resume_email_save()
	if _email_waiting_for_account and not busy and not _refreshing: refresh()
	return true
func _process(delta: float):
	if not _email_waiting_for_account: return
	_email_setup_elapsed += delta
	if _email_setup_elapsed >= EMAIL_SETUP_TIMEOUT:
		_email_local_fallback("Account setup timed out.")
func _email_local_fallback(reason: String):
	_email_waiting_for_account = false; email_busy = false; email_pending = false
	_email_needs_store = false
	email_message = reason+" Email saved on this device only. Not verified. You can retry in Settings."
	email_flow_changed.emit()
func _resume_email_save():
	if not _email_waiting_for_account or busy or _refreshing: return
	if _account_unavailable:
		_email_local_fallback("The account server is unavailable."); return
	if not email_capability_known or not store.online_ready(): return
	if not email_capable:
		_email_local_fallback("Email verification isn't available on this server."); return
	_email_waiting_for_account = false; email_pending = true
	_request_email_store()
func _stop_email_setup(message: String):
	if not _email_waiting_for_account: return
	_email_waiting_for_account = false; email_busy = false; email_pending = false
	email_message = message; email_flow_changed.emit()
func edit_email():
	if email_busy: return
	email_challenge = {}; email_pending = false; email_message = ""
	email_flow_changed.emit()
func request_email_verification():
	if not email_online_enabled() or email_busy: return
	var now = Time.get_unix_time_from_system()
	if now < maxf(email_retry_until,Store.email_timestamp(str(email_challenge.get("resend_available_at","")))): return
	if _email_needs_store: _request_email_store(); return
	email_pending = true; email_busy = true; email_message = "Sending a code…"
	api.submit("/me/email/verification",HTTPClient.METHOD_POST,{},"email_request",store.data.device_token)
	email_flow_changed.emit()
func _request_email_store():
	email_busy = true; email_message = "Saving email…"
	api.submit("/me",HTTPClient.METHOD_PATCH,{"email":store.data.email},"email_store",store.data.device_token)
	email_flow_changed.emit()
func confirm_email(value: String):
	if not email_online_enabled() or email_busy or email_challenge.is_empty() or Time.get_unix_time_from_system() < email_retry_until: return
	var code = value.replace(" ","").strip_edges()
	if code.length() != 6 or not code.is_valid_int() or code.contains("+") or code.contains("-"):
		error.emit("Enter the 6-digit code from your email."); return
	email_busy = true; email_message = "Checking code…"
	api.submit("/me/email/verification/confirm",HTTPClient.METHOD_POST,{"challenge_id":email_challenge.challenge_id,"code":code},"email_confirm",store.data.device_token)
	email_flow_changed.emit()
func continue_without_email():
	_stop_email_setup("")
	store.skip_email()
func _ready():
	api.completed.connect(_completed); add_child(api)
func refresh():
	if busy or _refreshing: return
	if store.complete() and (store.data.pending_sync or not store.has_device_token()): sync_pending()
	elif store.has_device_token():
		_refreshing = true; _account_unavailable = false
		api.submit("/me",HTTPClient.METHOD_GET,{},"me",store.data.device_token)
func sync_pending():
	if busy or not store.complete() or store.online_ready(): return
	store.data.pending_sync = true; store.save()
	_name_draft = store.data.screen_name; _consent = {}
	for key in ["tos_version","privacy_version","accepted_at","age_confirmed"]: _consent[key] = store.data[key]
	_syncing = true; busy = true; _account_unavailable = false
	_submit_registration()
func create_screen_name(value: String):
	if busy: return
	var clean = value.strip_edges()
	if not Store.valid_screen_name(clean):
		error.emit("Choose a screen name with 1–24 characters."); return
	_name_draft = clean; _consent = Store.consent_payload(); busy = true; _syncing = false; _account_unavailable = false
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
func _recover_device(operation: String):
	# Discard queued requests too: every one carries the invalid bearer token.
	api.cancel_all(); _refreshing = false
	store.data.device_token = ""; store.data.pending_sync = true
	store.data.email_status = "not_verified"; store.data.email_verified_at = ""; store.save()
	email_capable = false; email_capability_known = false; _account_unavailable = false
	if not busy:
		_name_draft = store.data.screen_name; _consent = {}
		for key in ["tos_version","privacy_version","accepted_at","age_confirmed"]: _consent[key] = store.data[key]
		_syncing = true
	_rename = ""
	# A challenge belongs to the old account. Restore the saved address and send
	# a new code after registration, never replay an old confirmation.
	var resume_email = operation in ["email_store","email_request","email_confirm"] or _email_waiting_for_account or email_pending
	var repeated_email_recovery = resume_email and _email_recovery_attempted
	email_challenge = {}; email_retry_until = 0.0
	if resume_email:
		if not _email_waiting_for_account: _email_setup_elapsed = 0.0
		_email_waiting_for_account = true; _email_needs_store = true
		_email_recovery_attempted = true
		email_busy = true; email_pending = false
		email_message = "Setting up your account…"; email_flow_changed.emit()
	if _recovering_device or repeated_email_recovery or not Store.valid_screen_name(_name_draft) or str(_consent.get("accepted_at","")).is_empty():
		# A broken/repeatedly rejected fresh credential must not loop forever.
		busy = false; _syncing = false; _recovering_device = false
		store.data.registration_rejected = true; store.save()
		var message = "Couldn't set up your account. Please create your screen name again."
		_stop_email_setup(message); error.emit(message); return
	_recovering_device = true; busy = true
	_submit_registration()
func _completed(operation: String, response: int, data: Dictionary, problem: String):
	if response == 401 and operation in ["me","consent","rename","hero","email_store","email_request","email_confirm"]:
		_recover_device(operation); return
	if operation == "me": _refreshing = false
	if operation in ["email_store","email_request","email_confirm"]:
		_email_completed(operation,response,data,problem); return
	if not problem.is_empty():
		if operation in ["register","consent"]:
			if operation == "consent" and response == 400 and _legacy_consent_api(problem):
				_finish_registration(false); return
			if _is_outage(response,problem):
				# A chosen name and the actual consent are enough for local play. No
				# substitute credential is created; live rooms wait for registration.
				_finish_registration(true); return
			busy = false
			var recovering = _recovering_device; _recovering_device = false
			if recovering and response == 409: problem = "That screen name is taken. Please choose another screen name."
			_stop_email_setup(problem)
			if _syncing or recovering:
				# A reachable server rejected an offline name. Resolve it on the
				# name screen, including after restart, without discarding consent.
				store.data.registration_rejected = true; store.save(); _syncing = false
				error.emit(problem); sync_finished.emit(); return
		if operation == "rename": _rename = ""
		if operation == "me":
			_account_unavailable = _is_outage(response,problem)
			if not _account_unavailable: _stop_email_setup(problem)
		error.emit(problem); _resume_email_save(); return
	var player = data.get("player",data)
	if not player is Dictionary:
		if operation in ["register","consent"]: _finish_registration(true)
		else:
			_account_unavailable = true
			error.emit("Online server not available. Invalid player response."); _resume_email_save()
		return
	match operation:
		"register":
			if not store.keep_device(str(data.get("token","")),_name_draft):
				_finish_registration(true); return
			_accept_email_player(player)
			_patch_consent()
		"consent":
			_accept_email_player(player)
			_finish_registration(false,str(player.get("screen_name",_name_draft)))
		"rename":
			_accept_email_player(player)
			store.data.screen_name = str(player.get("screen_name",_rename)); store.save()
			_rename = ""; name_updated.emit(store.data.screen_name)
		"me":
			_accept_email_player(player)
			if player.get("screen_name") is String and Store.valid_screen_name(player.screen_name):
				store.data.screen_name = player.screen_name; store.save(); name_updated.emit(player.screen_name)
			player_received.emit(player)
		"hero": _accept_email_player(player)
	_resume_email_save()

func _accept_email_player(player: Dictionary, replace_email: bool = false):
	email_capability_known = true; _account_unavailable = false
	var capabilities = player.get("capabilities",{})
	email_capable = capabilities is Dictionary and capabilities.get("email",false) == true
	var server_email = player.get("email","")
	if not server_email is String: server_email = ""
	if email_capable and (replace_email or store.data.email.is_empty()) and Store.valid_email(server_email):
		store.data.email = server_email
	store.data.email_status = "not_verified"; store.data.email_verified_at = ""
	# A server status applies only to the address it describes, never a local draft.
	if email_capable and not server_email.is_empty() and server_email.to_lower() == store.data.email.to_lower():
		var status = str(player.get("email_status","none"))
		store.data.email_status = "verified" if status == "verified" else "not_verified"
		var verified_at = player.get("email_verified_at")
		if verified_at is String: store.data.email_verified_at = verified_at
	store.save()
	email_changed.emit(store.data.email,store.data.email_status)
	email_flow_changed.emit()

func _email_completed(operation: String, response: int, data: Dictionary, problem: String):
	email_busy = false
	if not problem.is_empty():
		match response:
			502:
				email_message = "The email service could not send your code. Try Send code again. Not verified." if operation == "email_request" else "The email service could not complete this step. Email saved on this device, not verified. Try again."
			503:
				if "not available on this server yet" in problem.to_lower():
					email_message = "Email delivery is not configured. No code was sent. Email saved on this device, not verified."
				else:
					email_message = "Account service temporarily unavailable. Email saved on this device, not verified. Try again shortly."
			429:
				var seconds = maxi(0,int(data.get("retry_after_seconds",60)))
				email_retry_until = Time.get_unix_time_from_system()+seconds
				email_message = "Please wait %d seconds before trying again." % seconds
			404:
				email_message = "Please request a new code. This code could not be found."
				if operation == "email_confirm": email_challenge = {}
			_: email_message = str(data.get("error",problem))
		email_flow_changed.emit(); return
	if operation == "email_request":
		if not data.get("challenge_id") is String or str(data.get("challenge_id","")).is_empty():
			email_message = "Email isn't available right now"
		else:
			email_challenge = data.duplicate(true); email_retry_until = 0.0
			_email_recovery_attempted = false
			email_message = "Code sent. You can continue without verifying."
		email_flow_changed.emit(); return
	var player = data.get("player",data)
	if not player is Dictionary:
		email_message = "Email isn't available right now"; email_flow_changed.emit(); return
	_accept_email_player(player,true)
	if operation == "email_store":
		_email_needs_store = false
		if store.data.email_status != "verified" and email_online_enabled():
			request_email_verification(); return
	else:
		email_challenge = {}
	email_pending = false
	email_message = "Email verified." if store.data.email_status == "verified" else "Email saved. Not verified."
	email_flow_changed.emit()

func _finish_registration(pending: bool, confirmed_name: String = ""):
	store.data.pending_sync = pending; store.data.registration_rejected = false
	store.accept_consent(confirmed_name if Store.valid_screen_name(confirmed_name) else _name_draft,_consent)
	busy = false
	_recovering_device = false; _account_unavailable = pending
	var was_syncing = _syncing; _syncing = false
	name_updated.emit(store.data.screen_name)
	if was_syncing: sync_finished.emit()
	else: onboarding_complete.emit()
	_resume_email_save()

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

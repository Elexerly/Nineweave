extends RefCounted
## Separate from character-select onboarding. No room/seat credential is persisted here.
const TOS_VERSION = "2026-11-15"
const PRIVACY_VERSION = "2026-11-15"
var deletion_marker_io: Callable
var deletion_reset_required = false
var deletion_reset_reason = ""
var path: String
var data: Dictionary = {"signed_out":false,"deletion_uncertain":false,"deletion_resolution":"","device_token":"","screen_name":"","tos_version":"","privacy_version":"","accepted_at":"","age_confirmed":false,"pending_sync":false,"registration_rejected":false,"email":"","email_status":"not_verified","email_verified_at":"","email_prompt_done":false}
func _init(file_path: String = "user://nineweave-device.cfg"):
	path = file_path; data = data.duplicate(true)
	var cfg = ConfigFile.new()
	if cfg.load(path) == OK:
		for key in data:
			var value = cfg.get_value("device",key,data[key])
			if typeof(value) == typeof(data[key]): data[key] = value
	if not str(data.device_token).is_empty() and not str(data.device_token).begins_with("nwd_"):
		data.device_token = ""
	# Cached config never establishes verified ownership; refresh from the server.
	data.email_status = "not_verified"
	data.email_verified_at = ""
	if not str(data.email).is_empty() and not valid_email(data.email): data.email = ""
	# user:// flush is asynchronous on web; a synchronous non-secret marker wins
	# over stale filesystem credentials after an abrupt tab close.
	if OS.has_feature("web"): merge_deletion_marker()
func merge_deletion_marker():
	var state = _deletion_marker("read")
	if state.is_empty(): return
	if state == "pending" or state == "error":
		data.deletion_uncertain = true; return
	if state.begins_with("deleted:") or state.begins_with("recovered:") or state.begins_with("cleared:") or state.begins_with("signedout:"):
		var nonce = state.get_slice(":",1)
		if not nonce.is_empty() and data.deletion_resolution == nonce:
			data.deletion_uncertain = false; deletion_reset_required = false; return
		if state.begins_with("deleted:") or state.begins_with("cleared:") or state.begins_with("signedout:"):
			for key in data: data[key] = false if data[key] is bool else ""
			data.signed_out = state.begins_with("signedout:")
			deletion_reset_required = true; deletion_reset_reason = state.get_slice(":",0)
		else: data.deletion_uncertain = true
func _deletion_marker(operation: String) -> String:
	if deletion_marker_io.is_valid(): return str(deletion_marker_io.call(operation))
	if not OS.has_feature("web"): return "" if operation == "read" else "ok"
	var result = JavaScriptBridge.eval(deletion_marker_script(operation),true)
	return str(result) if result != null else "error"
func deletion_marker_script(operation: String) -> String:
	var suffix = JSON.stringify(":"+path.sha256_text())
	var code = "(function(){try{var k='nineweave-deletion:'+location.pathname.replace(/index[.]html$/,'')+"+suffix+";"
	if operation == "read": code += "return localStorage.getItem(k)||'';"
	else:
		var value = JSON.stringify(operation.trim_prefix("write:"))
		code += "var v="+value+";localStorage.setItem(k,v);return localStorage.getItem(k)===v?'ok':'error';"
	return code+"}catch(e){return 'error';}})()"
func set_deletion_uncertain(value: bool) -> bool:
	if not value: return mark_deletion_resolved(false)
	if _deletion_marker("write:pending") != "ok": return false
	data.deletion_uncertain = true
	return save()
func mark_deletion_resolved(deleted: bool, terminal_kind: String = "") -> bool:
	# Keep the terminal marker. A matching cfg nonce proves these credentials
	# were persisted after resolution; stale cfg must never recreate an account.
	var nonce = Crypto.new().generate_random_bytes(16).hex_encode()
	var kind = terminal_kind if terminal_kind in ["cleared","signedout"] else ("deleted" if deleted else "recovered")
	if _deletion_marker("write:"+kind+":"+nonce) != "ok":
		data.deletion_uncertain = true; return false
	var prior_resolution = data.deletion_resolution
	data.deletion_resolution = nonce; data.deletion_uncertain = false
	if not save():
		data.deletion_resolution = prior_resolution
		data.deletion_uncertain = true; deletion_reset_required = true; return false
	deletion_reset_required = false
	return true
func complete() -> bool:
	return not data.signed_out and valid_screen_name(data.screen_name) and data.tos_version == TOS_VERSION and data.privacy_version == PRIVACY_VERSION and not str(data.accepted_at).is_empty() and data.age_confirmed and not data.registration_rejected
func has_device_token() -> bool:
	return str(data.device_token).begins_with("nwd_") and str(data.device_token).length() > 4
func online_ready() -> bool:
	return complete() and has_device_token() and not data.pending_sync and not data.deletion_uncertain
static func valid_screen_name(value: String) -> bool:
	var clean = value.strip_edges()
	return not clean.is_empty() and clean.length() <= 24
static func consent_payload(utc: String = "") -> Dictionary:
	return {"tos_version":TOS_VERSION,"privacy_version":PRIVACY_VERSION,"accepted_at":utc if not utc.is_empty() else Time.get_datetime_string_from_system(true)+"Z","age_confirmed":true}
func save():
	var cfg = ConfigFile.new()
	for key in data: cfg.set_value("device",key,data[key])
	if cfg.save(path+".tmp") != OK: return false
	return DirAccess.rename_absolute(path+".tmp",path) == OK
func keep_device(credential: String, screen_name: String):
	if not credential.begins_with("nwd_") or credential.length() <= 4: return false
	data.device_token = credential; data.screen_name = screen_name; save(); return true
func accept_consent(screen_name: String, payload: Dictionary):
	data.screen_name = screen_name
	for key in ["tos_version","privacy_version","accepted_at","age_confirmed"]: data[key] = payload[key]
	save()
static func valid_email(value: String) -> bool:
	var clean = value.strip_edges()
	if clean.length() > 254: return false
	var parts = clean.split("@")
	if parts.size() != 2 or parts[0].length() > 64 or parts[0].begins_with(".") or parts[0].ends_with(".") or ".." in parts[0]: return false
	var pattern = RegEx.new()
	pattern.compile("^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$")
	return pattern.search(clean) != null
func keep_email(value: String) -> bool:
	if not valid_email(value): return false
	data.email = value.strip_edges(); data.email_status = "not_verified"; data.email_verified_at = ""; data.email_prompt_done = true
	save(); return true
static func email_timestamp(utc: String) -> float:
	# API timestamps are UTC, with optional fractional seconds and a trailing Z.
	if utc.is_empty(): return 0.0
	return float(Time.get_unix_time_from_datetime_string(utc.trim_suffix("Z").split(".")[0]))
func skip_email():
	data.email_prompt_done = true; save()

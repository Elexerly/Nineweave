extends RefCounted
## Separate from character-select onboarding. No room/seat credential is persisted here.
const TOS_VERSION = "2026-11-15"
const PRIVACY_VERSION = "2026-11-15"
var path: String
var data: Dictionary = {"device_token":"","screen_name":"","tos_version":"","privacy_version":"","accepted_at":"","age_confirmed":false,"email":"","email_status":"not_verified","email_prompt_done":false}
func _init(file_path: String = "user://nineweave-device.cfg"):
	path = file_path; data = data.duplicate(true)
	var cfg = ConfigFile.new()
	if cfg.load(path) == OK:
		for key in data:
			var value = cfg.get_value("device",key,data[key])
			if typeof(value) == typeof(data[key]): data[key] = value
	if not str(data.device_token).is_empty() and not str(data.device_token).begins_with("nwd_"):
		data.device_token = ""
	# Only a future authenticated server response may establish verified ownership.
	data.email_status = "not_verified"
	if not str(data.email).is_empty() and not valid_email(data.email): data.email = ""
func complete() -> bool:
	return str(data.device_token).begins_with("nwd_") and not str(data.screen_name).strip_edges().is_empty() and data.tos_version == TOS_VERSION and data.privacy_version == PRIVACY_VERSION and not str(data.accepted_at).is_empty() and data.age_confirmed
static func consent_payload(utc: String = "") -> Dictionary:
	return {"tos_version":TOS_VERSION,"privacy_version":PRIVACY_VERSION,"accepted_at":utc if not utc.is_empty() else Time.get_datetime_string_from_system(true)+"Z","age_confirmed":true}
func save():
	var cfg = ConfigFile.new()
	for key in data: cfg.set_value("device",key,data[key])
	cfg.save(path)
func keep_device(credential: String, screen_name: String):
	if not credential.begins_with("nwd_"): return false
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
	data.email = value.strip_edges(); data.email_status = "not_verified"; data.email_prompt_done = true
	save(); return true
func skip_email():
	data.email_prompt_done = true; save()

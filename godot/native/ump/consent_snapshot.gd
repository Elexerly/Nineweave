extends Node
## Read-only authoritative UMP state. No consent form, ad initialization, persisted grant,
## enum approximation, automatic refresh or production activation.
signal changed
signal snapshot_ready(allowed: bool)
const MAX_AGE_SECONDS = 5.0
var time_source: Callable
var _bridge
var _nonce = ""
var _sequence = 0
var _requested_at = -1.0
var _allowed = false
var _privacy = "unknown"
var _pending = false
func _now() -> float:
	return float(time_source.call()) if time_source.is_valid() else Time.get_ticks_msec()/1000.0
func initialize() -> bool:
	if OS.get_name() != "iOS" or not Engine.has_singleton("NineweaveConsent"): return false
	return attach_bridge(Engine.get_singleton("NineweaveConsent"))
func attach_bridge(bridge) -> bool:
	invalidate()
	_bridge = null
	if not is_instance_valid(bridge): return false
	if not bridge.has_method("request_snapshot") or not bridge.has_method("pop_snapshot"): return false
	_bridge = bridge
	return true
func invalidate():
	_sequence += 1; _nonce = ""; _requested_at = -1
	_pending = false; _allowed = false; _privacy = "unknown"
	changed.emit()
func refresh() -> bool:
	# Coordinator calls AFTER launch UMP update/form and before every load/show.
	# Deny while pending. Duplicate callers cannot queue unlimited native reads.
	if _pending: return false
	invalidate()
	if not is_instance_valid(_bridge): return false
	_nonce = "%s:%s" % [get_instance_id(),_sequence]
	_requested_at = _now(); _pending = true
	_bridge.request_snapshot(_nonce)
	return true
func pending_nonce() -> String: return _nonce
func allowed() -> bool:
	return is_instance_valid(_bridge) and _allowed and not _pending and _requested_at >= 0 and _now()-_requested_at <= MAX_AGE_SECONDS
func privacy_options_status() -> String:
	return _privacy if is_instance_valid(_bridge) and _requested_at >= 0 and not _pending and _now()-_requested_at <= MAX_AGE_SECONDS else "unknown"
func _process(_delta):
	if _requested_at >= 0 and _now()-_requested_at > MAX_AGE_SECONDS:
		var was_pending = _pending
		invalidate()
		if was_pending: snapshot_ready.emit(false)
	if not is_instance_valid(_bridge):
		if _allowed or _pending: invalidate()
		return
	for _i in range(32):
		var raw = _bridge.pop_snapshot()
		if not raw is String or raw.is_empty(): break
		var parser = JSON.new()
		if parser.parse(raw) != OK: continue
		var data = parser.data
		if not data is Dictionary or not _pending or str(data.get("nonce","")) != _nonce: continue
		_pending = false
		_allowed = data.get("can_request_ads") is bool and data.get("can_request_ads") == true and _now()-_requested_at <= MAX_AGE_SECONDS
		var status = data.get("privacy_options_status", "unknown")
		_privacy = status if status in ["required","not_required","unknown"] else "unknown"
		changed.emit(); snapshot_ready.emit(allowed())
func _notification(what):
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]: invalidate()
func _exit_tree(): invalidate(); _bridge = null

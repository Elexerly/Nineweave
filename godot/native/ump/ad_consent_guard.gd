extends Node
## Inactive composition boundary. Each operation needs its own fresh UMP snapshot.
## No SDK initialization/load/show/form is performed here; caller executes only on true.
var reader
var entitlement_allows_ads: Callable
var _callback: Callable
var _nonce = ""
var _privacy_open = false
func setup(snapshot_reader, entitlement_check: Callable):
	cancel()
	if is_instance_valid(reader) and reader.snapshot_ready.is_connected(_snapshot_ready): reader.snapshot_ready.disconnect(_snapshot_ready)
	reader = snapshot_reader; entitlement_allows_ads = entitlement_check
	if is_instance_valid(reader): reader.snapshot_ready.connect(_snapshot_ready)
func privacy_options_reachable() -> bool:
	# Availability of the entry point never follows the short-lived ad grant.
	return is_instance_valid(reader)
func request_load(callback: Callable) -> bool: return _request(callback)
func request_show(callback: Callable) -> bool: return _request(callback)
func _request(callback: Callable) -> bool:
	if _callback.is_valid(): return false
	if not callback.is_valid(): return false
	if _privacy_open or not is_instance_valid(reader) or not entitlement_allows_ads.is_valid() or not bool(entitlement_allows_ads.call()):
		callback.call(false); return true
	_callback = callback
	# Do NOT read cached allowed(): load and show each request a new native read.
	if not reader.refresh():
		_finish(false); return true
	_nonce = reader.pending_nonce()
	return true
func _snapshot_ready(allowed: bool):
	if not _callback.is_valid(): return
	var valid = is_instance_valid(reader) and not _nonce.is_empty() and reader.pending_nonce() == _nonce
	_finish(allowed and valid and not _privacy_open and entitlement_allows_ads.is_valid() and bool(entitlement_allows_ads.call()))
func _finish(allowed: bool):
	var callback = _callback; _callback = Callable(); _nonce = ""
	if callback.is_valid(): callback.call(allowed)
func cancel():
	if is_instance_valid(reader): reader.invalidate()
	_finish(false)
func before_privacy_form():
	# Invoke BEFORE calling the actual SDK form presenter, never afterwards.
	_privacy_open = true; cancel()
func after_privacy_form():
	_privacy_open = false
	if is_instance_valid(reader): reader.invalidate()
func _notification(what):
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT]: cancel()
func _exit_tree():
	cancel()
	if is_instance_valid(reader) and reader.snapshot_ready.is_connected(_snapshot_ready): reader.snapshot_ready.disconnect(_snapshot_ready)

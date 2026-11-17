extends Node
## No entitlement/consent/SDK => no ads. This cannot grant a purchase.
signal presenting_changed(active: bool)
var provider
var entitlements
var consent_allowed: Callable
var enabled = false
var due = false
var busy = false
var _marked = false
var _generation = 0
var _continuation: Callable
var _callback: Callable
func begin_match():
	_marked = false
	if can_serve(): provider.preload_ad()
func match_completed():
	if _marked: return
	_marked = true; due = true
func can_serve() -> bool:
	return enabled and is_instance_valid(provider) and is_instance_valid(entitlements) and entitlements.entitlement_ready() and not entitlements.ads_removed() and consent_allowed.is_valid() and bool(consent_allowed.call())
func before_next(continuation: Callable):
	if busy: return
	if not due:
		continuation.call(); return
	due = false
	if not can_serve() or not provider.is_ready():
		continuation.call(); return
	busy = true; _generation += 1; _continuation = continuation
	var generation = _generation
	_callback = func(): _finish(generation)
	provider.completed.connect(_callback)
	presenting_changed.emit(true)
	if not provider.show_interstitial(): _finish(generation)
func _finish(generation: int):
	if not busy or generation != _generation: return
	var continuation = _continuation
	_disconnect(); busy = false; _continuation = Callable()
	presenting_changed.emit(false)
	if continuation.is_valid(): continuation.call()
func cancel():
	# Cancel navigation, not the native presentation. Keep muted/busy until SDK
	# dismissal so a second action cannot start a clock under the existing ad.
	_continuation = Callable()
func skip_unsafe_boundary():
	# Online tournament backend already starts clocks; never block it with an ad.
	cancel(); due = false
func _disconnect():
	if is_instance_valid(provider) and _callback.is_valid() and provider.completed.is_connected(_callback): provider.completed.disconnect(_callback)
	_callback = Callable()
func _exit_tree():
	_generation += 1; _disconnect(); _continuation = Callable()
	if busy: busy = false; presenting_changed.emit(false)

extends Node
## Native-only verified StoreKit entitlement. Never reads profile/server purchases.
signal entitlement_changed
signal product_changed
signal status_changed(state: String)
signal store_error(message: String)
var _store: Object
var _product_id := ""
var _ready_entitlement := false
var _owned := false
var localized_price := ""
var _started := false

func initialize(product_id: String) -> void:
	if _started or product_id.is_empty(): return
	if OS.get_name() != "iOS" or not Engine.has_singleton("NineweaveStoreKit"): return
	_product_id = product_id
	_store = Engine.get_singleton("NineweaveStoreKit")
	_started = true
	_store.configure(product_id)

func entitlement_ready() -> bool: return _ready_entitlement
func ads_removed() -> bool: return _ready_entitlement and _owned
func purchase() -> void:
	if _started: _store.purchase()
func restore() -> void:
	# Call only from the user's explicit Restore Purchases button.
	if _started: _store.restore()
func refresh() -> void:
	if _started: _store.refresh()
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED: refresh()
func _process(_delta: float) -> void:
	if not _started: return
	for _index in range(32):
		var raw: String = _store.pop_event()
		if raw.is_empty(): break
		var event = JSON.parse_string(raw)
		if event is Dictionary: _handle_event(event)

func _handle_event(event: Dictionary) -> void:
	match str(event.get("kind", "")):
		"configured":
			if is_instance_valid(_store): _store.query_product()
		"entitlement":
			if _product_id.is_empty() or event.get("product_id") != _product_id or event.get("verified") != true: return
			if not event.get("owned") is bool: return
			_owned = event.owned
			_ready_entitlement = true
			# Deliver to consumers before acknowledging the native transaction.
			entitlement_changed.emit()
			var token: String = str(event.get("delivery_token", ""))
			if not token.is_empty() and is_instance_valid(_store): _store.acknowledge(token)
		"product":
			if event.get("product_id") != _product_id: return
			localized_price = str(event.get("price", ""))
			product_changed.emit()
		"purchase", "restore": status_changed.emit(str(event.get("state", "")))
		"error":
			if event.get("operation") == "verification":
				_ready_entitlement = false
				entitlement_changed.emit()
			store_error.emit(str(event.get("message", "Store unavailable.")))

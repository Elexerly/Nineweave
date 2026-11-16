extends Node
## Isolated unauthenticated sign-in. Never registers or replaces an account on failure.
const API = preload("res://net/json_api.gd")
const Store = preload("res://net/device_store.gd")
signal changed
signal recovered(token: String, player: Dictionary)
var api = API.new()
var active = false
var busy = false
var email = ""
var code = ""
var challenge: Dictionary = {}
var message = ""
var retry_until = 0.0
func _ready():
	api.completed.connect(_completed); add_child(api)
func begin():
	cancel(); active = true
func cancel():
	active = false; busy = false
	# Retire the entire HTTP boundary so an old callback cannot target a new attempt.
	var factory = api.request_factory
	var base = api.base_url
	api.cancel_all()
	if api.completed.is_connected(_completed): api.completed.disconnect(_completed)
	if api.get_parent() == self: remove_child(api)
	api.queue_free(); api = API.new(); api.request_factory = factory; api.base_url = base
	api.completed.connect(_completed); add_child(api)
	email = ""; code = ""; challenge = {}; message = ""; retry_until = 0.0
func request_code():
	if not active or busy or Time.get_unix_time_from_system() < maxf(retry_until,Store.email_timestamp(str(challenge.get("resend_available_at","")))): return
	if not Store.valid_email(email):
		message = "Enter a valid email address."; changed.emit(); return
	busy = true; message = "Requesting a sign-in code…"; code = ""
	api.submit("/auth/email/recover",HTTPClient.METHOD_POST,{"email":email.strip_edges()},"recover")
	changed.emit()
func confirm():
	if not active or busy or challenge.is_empty() or Time.get_unix_time_from_system() < retry_until: return
	var clean = code.strip_edges()
	if clean.length() != 6 or not clean.is_valid_int() or clean.contains("+") or clean.contains("-"):
		message = "Enter the 6-digit code from your email."; changed.emit(); return
	busy = true; message = "Signing in…"
	api.submit("/auth/email/recover/confirm",HTTPClient.METHOD_POST,{"challenge_id":challenge.challenge_id,"code":clean},"confirm")
	changed.emit()
func _completed(operation: String, response: int, data: Dictionary, problem: String):
	if not active or not busy: return
	busy = false
	if not problem.is_empty() or response < 200 or response >= 300:
		if response == 429:
			retry_until = Time.get_unix_time_from_system()+maxi(1,int(data.get("retry_after_seconds",60)))
			message = "Too many attempts. Please wait a minute and try again."
		elif response == 0 or response >= 500:
			message = "Sign-in is unavailable right now. Please try again."
		else: message = "Code invalid or expired. Check it or request a new code."
		changed.emit(); return
	if operation == "recover":
		if not data.get("challenge_id") is String or str(data.challenge_id).is_empty():
			message = "Sign-in is unavailable right now. Please try again."
		else:
			challenge = data.duplicate(true)
			message = "If this email belongs to a verified account, a code will arrive. Check spam too."
		changed.emit(); return
	var player = data.get("player",{})
	var token = str(data.get("token",""))
	if not player is Dictionary or not Store.valid_screen_name(str(player.get("screen_name",""))) or not token.begins_with("nwd_") or token.length() <= 4 or str(data.get("player_id","")).is_empty() or player.get("email_status") != "verified" or not Store.valid_email(str(player.get("email",""))):
		message = "Couldn't confirm sign-in. Please request a new code."; changed.emit(); return
	active = false; code = ""; challenge = {}
	recovered.emit(token,player)

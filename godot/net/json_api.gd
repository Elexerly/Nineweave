extends Node
## Shared JSON boundary. Injectable HTTPRequest factory keeps every test off network.
const LIVE_ORIGIN = "https://nineweave.grok.me"
const API_PATH = "/api/nineweave"
const Clock = preload("res://net/turn_clock.gd")
signal completed(operation: String, response: int, data: Dictionary, problem: String)
var base_url: String = LIVE_ORIGIN
var request_factory: Callable
var _request
var _queue: Array = []
var _current: Dictionary = {}
static func origin_base(origin: String) -> String:
	# HTTPRequest rejects scheme-less URLs (ERR_INVALID_PARAMETER), so the live
	# page must use its absolute origin, never "" or a relative path.
	return LIVE_ORIGIN
static func request_url(base: String, path: String) -> String:
	var absolute = base if base.begins_with("https://") or base.begins_with("http://") else LIVE_ORIGIN
	return absolute+API_PATH+path
static func authorization(credential: String) -> PackedStringArray:
	var headers = PackedStringArray(["Content-Type: application/json"])
	if not credential.is_empty(): headers.append("Authorization: Bearer "+credential)
	return headers
func _ready():
	if OS.has_feature("web"):
		# Local QA only: ?api=http://127.0.0.1:PORT is honoured on a localhost page, never elsewhere.
		var local = Clock.api_override(str(JavaScriptBridge.eval("window.location.hostname")),str(JavaScriptBridge.eval("(new URLSearchParams(window.location.search)).get('api')||''")))
		if not local.is_empty(): base_url = local
		elif base_url == LIVE_ORIGIN: base_url = origin_base(str(JavaScriptBridge.eval("window.location.origin")))
	_request = request_factory.call() if request_factory.is_valid() else HTTPRequest.new()
	_request.timeout = 8.0; add_child(_request)
	_request.request_completed.connect(_complete)
	_start_next()
func submit(path: String, method: int, body: Dictionary, operation: String, credential: String = ""):
	_queue.append({"path":path,"method":method,"body":body.duplicate(true),"operation":operation,"credential":credential})
	_start_next()
func _start_next():
	if not is_instance_valid(_request) or not _current.is_empty() or _queue.is_empty(): return
	_current = _queue.pop_front()
	var item = _current
	var result = _request.request(request_url(base_url,item.path),authorization(item.credential),item.method,JSON.stringify(item.body) if item.method != HTTPClient.METHOD_GET else "")
	if result != OK:
		printerr("Nineweave API request could not be sent (error %d): %s" % [result,str(item.get("operation",""))])
		_finish(0,{},"Online server not available. Request could not be sent (error %d)." % result)
func _complete(result: int, response: int, _headers: PackedStringArray, body: PackedByteArray):
	if _current.is_empty(): return
	if result != HTTPRequest.RESULT_SUCCESS or response == 0:
		_finish(response,{},"Online server not available. Can't reach the server."); return
	var parser = JSON.new()
	var parse_error = parser.parse(body.get_string_from_utf8())
	var parsed = parser.data if parse_error == OK else null
	if not parsed is Dictionary:
		_finish(response,{},"Online server not available. Please try again."); return
	var problem = ""
	if response < 200 or response >= 300:
		problem = str(parsed.get("error",fallback_error(response)))
	_finish(response,parsed,problem)
static func fallback_error(response: int) -> String:
	match response:
		403: return "Wrong room password or permission denied."
		404: return "Room not found or expired. Check the code."
		409: return "This room is full, closed, or already yours."
		429: return "Too many requests. Please wait a moment and try again."
		_: return "Online server not available. Please try again."
func _finish(response: int, data: Dictionary, problem: String):
	var operation = str(_current.get("operation",""))
	_current = {}
	completed.emit(operation,response,data,problem)
	_start_next()
func cancel_all():
	_queue.clear(); _current = {}
	if is_instance_valid(_request): _request.cancel_request()

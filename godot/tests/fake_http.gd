extends Node
## Deterministic HTTPRequest replacement. No sockets, DNS or network calls.
signal request_completed(result: int, response: int, headers: PackedStringArray, body: PackedByteArray)
var timeout: float = 0
var requests: Array = []
var active: bool = false
var immediate_error: int = OK
func request(url: String, headers: PackedStringArray, method: int, body: String) -> int:
	requests.append({"url":url,"headers":headers,"method":method,"body":JSON.parse_string(body) if not body.is_empty() else {}})
	active = immediate_error == OK
	return immediate_error
func cancel_request(): active = false
func respond(response: int, data, result: int = HTTPRequest.RESULT_SUCCESS):
	active = false
	var body = data if data is String else JSON.stringify(data)
	request_completed.emit(result,response,PackedStringArray(),str(body).to_utf8_buffer())

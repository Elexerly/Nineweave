extends Node
## Separate from registration: deletion errors must never trigger replacement identity.
const API = preload("res://net/json_api.gd")
signal changed
signal deleted
var api = API.new()
var store
var _previous_uncertain = false
var stage = 0
var busy = false
var message = ""
var phrase = ""
func _ready():
	api.completed.connect(_completed); add_child(api)
func begin():
	if busy: return
	stage = 1; message = "An earlier deletion may have completed. No account will be automatically recreated. Retry deletion or sign in with your verified email to resolve it." if store != null and store.data.deletion_uncertain else ""; phrase = ""; changed.emit()
func proceed():
	if busy or stage != 1: return
	stage = 2; phrase = ""; changed.emit()
func cancel():
	if busy: return # Submitted deletion cannot honestly be canceled locally.
	stage = 0; phrase = ""; message = ""; changed.emit()
func submit(token: String, capable: bool):
	if busy or stage != 2 or phrase != "DELETE MY ACCOUNT" or not capable or not token.begins_with("nwd_") or token.length() <= 4: return
	if store == null: return
	_previous_uncertain = store.data.deletion_uncertain
	if not store.set_deletion_uncertain(true):
		message = "Cannot safely save deletion status on this device. No deletion request was sent."; changed.emit(); return
	busy = true; message = "Deleting your account. Please wait…"; changed.emit()
	api.submit("/me",HTTPClient.METHOD_DELETE,{"confirm":"DELETE MY ACCOUNT"},"delete_account",token)
func _completed(operation: String, response: int, data: Dictionary, problem: String):
	if operation != "delete_account" or not busy: return
	busy = false
	if response == 200 and problem.is_empty() and data.get("deleted") == true and data.get("retained_gameplay_label") == "####":
		stage = 0; phrase = ""; deleted.emit(); return
	if response == 409 and not _previous_uncertain:
		store.set_deletion_uncertain(false)
	phrase = "" # Every retry requires a fresh explicit final confirmation.
	match response:
		401: message = "Your session was rejected. Deletion may have completed. No replacement account was created. Sign in with your verified email to resolve this."
		409: message = "Finish or leave active matches. Active tournaments must finish or be canceled before deletion. Your account has not been deleted."
		503: message = "Deletion was not confirmed. It may have completed. Automatic account creation is blocked; retry shortly."
		_: message = "Deletion may have completed. Your local details are retained, but automatic account creation is blocked. Retry deletion or sign in to resolve."
	if response == 409 and _previous_uncertain: message = "This retry was blocked by active gameplay. An earlier deletion is still unresolved; sign in with your verified email to resolve it."
	changed.emit()

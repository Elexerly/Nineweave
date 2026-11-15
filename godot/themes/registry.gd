extends RefCounted
## Local cosmetic choices. This registry is deliberately absent from net/.
const DEFAULT_BACKGROUND = "crystal"
const DEFAULT_BOARD = "crystal"
const BACKGROUNDS = [
	{"id":"crystal","name":"Crystal Citadel","description":"The original navy, gold and frozen sky."},
	{"id":"tidal","name":"Tidal Ocean","description":"Pearl moonlight over slow, layered waves."},
	{"id":"desert","name":"Western Dusk","description":"Distant sandstone mesas beneath a copper sun."}
]
const BOARDS = [
	{"id":"crystal","name":"Crystal Classic","description":"Original Round 2 crystal marks and navy tiles."},
	{"id":"sandstone","name":"Sandstone Marble","description":"Warm veined stone, copper and turquoise pieces."}
]
static func valid(id: String, collection: Array) -> bool:
	for item in collection:
		if item.id == id: return true
	return false
static func item(id: String, collection: Array) -> Dictionary:
	for entry in collection:
		if entry.id == id: return entry
	return collection[0]
static func next(id: String, collection: Array) -> String:
	for i in range(collection.size()):
		if collection[i].id == id: return str(collection[(i+1)%collection.size()].id)
	return str(collection[0].id)

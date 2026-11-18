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
const BONUS_BACKGROUNDS = [
	{"id":"blizzard","name":"Blizzard","description":"Snowfall over ice-blue mountain silhouettes."},
	{"id":"tictactoe","name":"Tic Tac Toe","description":"Neon crosses and rings in a midnight grid."},
	{"id":"new_year","name":"New Year's Eve","description":"Gold fireworks and midnight confetti."},
	{"id":"fourth_july","name":"Fourth of July","description":"Red, white and blue starbursts."},
	{"id":"st_patrick","name":"St Patrick's Day","description":"Emerald shamrocks and golden sparks."}
]
const BACKGROUND_CODES = {"BLIZZARD":"blizzard","TICTACTOE":"tictactoe","010127":"new_year","0704027":"fourth_july","PATRICK":"st_patrick"}
const RESERVED_HERO_CODES = ["W2026","G2026","J2026","B2026","E2026","JB2026","T2026","JY2026","GM2026","D2026"]
static func available(unlocked: Array) -> Array:
	var result = BACKGROUNDS.duplicate(true)
	for entry in BONUS_BACKGROUNDS:
		if entry.id in unlocked: result.append(entry)
	return result
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

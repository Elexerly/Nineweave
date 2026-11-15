extends RefCounted
## Presentation state only. Weighted, deterministic local choices; no kernel RNG/state.
const EXPRESSIONS = ["neutral","smug_grin","panic","double_take","eye_roll","celebration","sulking"]
const CLIPS = {
	"react_nod":{"face":"neutral","duration":.65},
	"react_smirk":{"face":"smug_grin","duration":1.15},
	"react_startle":{"face":"double_take","duration":.95},
	"react_roll":{"face":"eye_roll","duration":1.2},
	"react_cheer":{"face":"celebration","duration":1.25},
	"react_panic":{"face":"panic","duration":1.2},
	"react_pout":{"face":"sulking","duration":1.3},
	"react_relief":{"face":"smug_grin","duration":1.3}
}
# [clip, weight], priority 0=ordinary move, 1=good move, 2=claim, 3=turn, 4=result.
const EVENTS = {
	"own_move":{"choices":[["react_nod",3],["react_smirk",1]],"priority":0},
	"opponent_move":{"choices":[["react_startle",1],["react_roll",2]],"priority":0},
	"own_claim":{"choices":[["react_cheer",3],["react_smirk",1]],"priority":2},
	"opponent_good":{"choices":[["react_startle",3],["react_roll",1]],"priority":1},
	"opponent_claim":{"choices":[["react_pout",2],["react_panic",2],["react_roll",1]],"priority":2},
	"near_loss":{"choices":[["react_panic",3],["react_startle",1]],"priority":3},
	"comeback":{"choices":[["react_relief",2],["react_cheer",2]],"priority":3},
	"win":{"choices":[["react_cheer",3],["react_smirk",1]],"priority":4},
	"loss":{"choices":[["react_pout",3],["react_panic",1]],"priority":4}
}
# Eye spacing, brow lift, asymmetric smile, pupil drift: each original hero has a face dialect.
const DIALECTS = [
	[1.0,-1.0,1.0,.0],[1.1,-2.0,1.8,.5],[.9,.8,.7,-.7],[.85,-2.0,.5,0],
	[1.05,1.0,2.2,.7],[.95,.0,.9,-.2],[1.15,-.6,2.7,1.2],[.9,-1.5,2.0,-.8],
	[1.15,1.2,.5,-.5],[1.1,1.7,1.6,.6],[.85,1.8,1.1,-1.0],[1.0,-.6,2.3,1.0]
]
var cooldown: float = 0
var age: float = 0
var remaining: float = 0
var current: String = ""
var event: String = ""
var priority: int = -1
var sequence: int = 0
func request(id: String, hero_index: int, reduced: bool = false) -> bool:
	if not EVENTS.has(id): return false
	var p: int = EVENTS[id].priority
	if cooldown > 0 and (p <= priority or p < 2): return false
	sequence += 1; var choices: Array = EVENTS[id].choices; var total = 0
	for choice in choices: total += int(choice[1])
	var pick = posmod(sequence*17+hero_index*7,total)
	for choice in choices:
		pick -= int(choice[1])
		if pick < 0: current = choice[0]; break
	event = id; priority = p; age = 0
	remaining = minf(.5,CLIPS[current].duration) if reduced else float(CLIPS[current].duration)
	cooldown = maxf(.85,remaining+.15)
	return true
func advance(delta: float):
	age += delta; cooldown = maxf(0,cooldown-delta); remaining = maxf(0,remaining-delta)
	if cooldown == 0: priority = -1
static func expression_for(hero_index: int, reaction_id: String) -> Dictionary:
	return {"id":CLIPS.get(reaction_id,{"face":"neutral"}).face,"dialect":DIALECTS[clampi(hero_index,0,11)]}

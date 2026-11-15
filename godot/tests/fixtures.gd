extends RefCounted
const Rules = preload("res://kernel/rules.gd")
static func position(patterns: Array, turn: int = 1, active: int = -1):
	var game = Rules.new()
	if not game.deserialize({"v":1,"cells":"".join(patterns),"turn":turn,"active":active,"history":[]}): push_error("Invalid test fixture")
	return game
static func big_tactic(player: int = 1, block: bool = false):
	var patterns: Array = []
	for b in range(9): patterns.append(".........")
	var owned = "XXXOO...." if player == 1 else "OOOXX...."
	var threat = "XX.OO...." if player == 1 else "OO.XX...."
	patterns[0] = owned; patterns[1] = owned; patterns[2] = threat
	return position(patterns,3-player if block else player,2)

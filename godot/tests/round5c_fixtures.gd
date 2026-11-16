extends RefCounted
const Rules = preload("res://kernel/rules.gd")
static func person(seed_value: int, name_value: String, hero: String) -> Dictionary:
	return {"seed":seed_value,"name":name_value,"hero":hero,"eliminated":false}
static func envelope(phase: String = "running") -> Dictionary:
	var players = [person(1,"Weaver","shard_jack"),person(2,"Kai","james_ii"),person(3,"Mo","cryon"),person(4,"Ana","aurelia"),person(5,"Bo","shard_jack"),person(6,"Cy","daphne")]
	var rounds = [
		[game(0,players[0],null,"done",null,"a",true),game(1,players[3],players[4],"live",{"a":3,"b":2}),game(2,players[1],null,"done",null,"a",true),game(3,players[2],players[5],"live",{"a":1,"b":2})],
		[game(0,players[0],null,"pending"),game(1,players[1],null,"pending")],
		[game(0,null,null,"pending")]]
	var t = Time.get_unix_time_from_system()
	return {"code":"T7KQ2M","status":phase,"size":8,"joined":6,"min_players":3,"bracket_size":8,
		"starts_at":iso(t+120),"starting_at":null,"server_now":iso(t),"private":false,"host":"Weaver","is_host":true,"cancel_reason":null,
		"you":{"seed":1,"name":"Weaver","hero":"shard_jack","state":"bye" if phase == "running" else "registered"},
		"players":players,"rounds":rounds if phase == "running" else [],"your_match":null,"champion":null,"poll_after_ms":4000 if phase == "running" else 5000}
static func game(slot: int, a, b, status: String, score = null, winner = null, bye: bool = false) -> Dictionary:
	return {"slot":slot,"a":a,"b":b,"status":status,"score":score,"winner":winner,"bye":bye,"end_reason":"bye" if bye else null}
static func iso(t: float) -> String: return Time.get_datetime_string_from_unix_time(int(t))+".000Z"
static func ready() -> Dictionary:
	return {"room_code":"QX7P2","token":"nws_r5c_seat","seat":2,"round":2,"slot":0,"status":"ready","opponent":{"name":"Ana","hero":"aurelia"},"ready_deadline":iso(Time.get_unix_time_from_system()+60)}
static func room(phase: String = "active") -> Dictionary:
	return {"code":"QX7P2","seat":2,"seq":0,"state":Rules.new().serialize(),"status":phase,"private":true,
		"opponent":"Ana","opponent_left":false,"characters":{"1":"aurelia","2":"shard_jack"},"match":{"round":1,"seat":2,"local":false,"remote":false},
		"result":{"winner":2} if phase == "finished" else null,"end_reason":"boards" if phase == "finished" else null,
		"protocol":2,"server_now":iso(Time.get_unix_time_from_system()),"poll_after_ms":1000,
		"you":{"name":"Weaver","hero":"shard_jack"},"players":{"1":{"name":"Ana","hero":"aurelia"},"2":{"name":"Weaver","hero":"shard_jack"}},
		"tournament":{"code":"T7KQ2M","round":2,"slot":0,"ready_deadline":iso(Time.get_unix_time_from_system()+60),"ready":{"you":true,"opponent":phase != "waiting"},"rematch":false}}

extends SceneTree
const L = preload("res://ui/layout.gd")
var checks = 0
var failures = 0
func ok(value: bool, msg: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",msg)
func _initialize(): run.call_deferred()
func run():
	var cases = [
		[390,844,"phone_portrait"],[360,640,"phone_portrait"],[430,932,"phone_portrait"],[375,667,"phone_portrait"],
		[844,390,"phone_landscape"],[932,430,"phone_landscape"],[667,375,"phone_landscape"],[568,320,"phone_landscape"],
		[768,1024,"tablet_portrait"],[1024,768,"landscape"],[1366,1024,"landscape"],[1280,720,"landscape"],[1920,1080,"landscape"],
		[1024,720,"duo_landscape"],[960,720,"duo_landscape"],[800,600,"duo_landscape"],[800,700,"duo_landscape"],[720,700,"duo_landscape"],[1180,820,"landscape"],
		[867,553,"duo_landscape"],[867,500,"duo_landscape"],[867,600,"duo_landscape"],[669,787,"duo_portrait"],[669,720,"duo_portrait"],[2601,1659,"duo_landscape"]]
	for case in cases:
		var s = Vector2(case[0],case[1]); inspect(s,Rect2(),case[2])
		if case[2] == "duo_landscape": inspect(s,Rect2(s.x*.5-10,0,20,s.y),case[2])
	inspect(Vector2(669,787),Rect2(323.5,0,22,787),"duo_landscape")
	var normal = L.compute(Vector2(867,553)); var large = L.compute(Vector2(2601,1659))
	ok(normal.board == large.board,"DPR3 same logical composition")
	# Producer-reported cases, pinned explicitly.
	var ipad = L.compute(Vector2(1366,1024))
	ok(ipad.hero_player.size.y == 0 and ipad.hero_opponent.size.y == 0,"1366x1024 no bust over the scorecards (live scorecard figures)")
	ok(normal.hero_player.size.y >= 150 and normal.hero_player_host == "character","867x553 player figure uses the Duo panel")
	var phone = L.compute(Vector2(390,844))
	ok(phone.hero_opponent.position.y > phone.controls.end.y and phone.hero_opponent.size.y >= 90,"390x844 rival bust mirrored at bottom-right, uncropped size")
	ok(phone.board.size.x == 370 and phone.board.position.x == 10,"390x844 edge-to-edge board (Round 3e) "+str(phone.board))
	print("NINEWEAVE_LAYOUT ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures," sizes=",cases.size())
	quit(0 if failures == 0 else 1)
func inspect(s: Vector2, hinge: Rect2, expected: String):
	var layout = L.compute(s,hinge)
	var id = str(s)+(" hinge" if hinge.size.x else "")
	ok(layout.mode == expected,id+" mode "+layout.mode)
	ok(is_equal_approx(layout.board.size.x,layout.board.size.y),id+" board square")
	var viewport = Rect2(Vector2.ZERO,layout.size).grow(.1)
	# Round 3b: corner characters never collide with the board or any HUD rect; an empty
	# rect means that side reacts in its scorecard. Present corners are readable busts.
	var hud = L.hud_rects(layout)
	for key in ["hero_player","hero_opponent"]:
		var corner: Rect2 = layout[key]
		if corner.size.y <= 0: continue
		ok(corner.size.y >= L.MIN_CORNER and corner.size.x >= 48,id+" readable corner "+key+" "+str(corner))
		ok(viewport.encloses(corner),id+" corner in view "+key)
		ok(not corner.intersects(layout.board),id+" corner never overlaps board "+key)
		if hinge.size.x: ok(not corner.intersects(layout.hinge),id+" corner hinge safe "+key)
		for other in hud:
			if key == "hero_player" and other == layout.hero_player_host:
				ok(hud[other].encloses(corner),id+" hosted corner inside "+other)
				continue
			ok(not corner.intersects(hud[other]),id+" corner "+key+" clear of HUD "+other+" "+str(corner)+" vs "+str(hud[other]))
		if key == "hero_player" and layout.hero_opponent.size.y > 0: ok(not corner.intersects(layout.hero_opponent),id+" corners apart")
	ok(not layout.message.intersects(layout.controls) and viewport.encloses(layout.message),id+" message lane clear of controls")
	if layout.mode == "duo_landscape": ok(layout.hero_player.size.y >= 120,id+" Duo player figure readable "+str(layout.hero_player))
	var rects = L.major_rects(layout)
	if layout.mode == "phone_portrait":
		# Round 3e: the header row holds back · TURN · gear, so the header is its two buttons.
		rects.erase("header")
		rects["home"] = Rect2(layout.header.position,Vector2(44,44))
		rects["settings"] = Rect2(layout.header.end.x-44,layout.header.position.y,44,44)
		ok(layout.info.size.y == 0,id+" no info panel on phone portrait")
	for key in rects:
		ok(viewport.encloses(rects[key]),id+" inside "+key+" "+str(rects[key]))
		for other in rects:
			if key < other: ok(not rects[key].intersects(rects[other]),id+" overlap "+key+" / "+other)
	ok(layout.controls.size.y >= 44 and layout.header.size.y >= 44,id+" 44px control targets")
	ok(not layout.board.intersects(layout.hinge) or hinge.size.x == 0,id+" hinge safe board")
	if hinge.size.x:
		for key in rects: ok(not rects[key].intersects(layout.hinge),id+" hinge safe "+key)

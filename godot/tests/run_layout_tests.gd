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
	print("NINEWEAVE_LAYOUT ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures," sizes=",cases.size())
	quit(0 if failures == 0 else 1)
func inspect(s: Vector2, hinge: Rect2, expected: String):
	var layout = L.compute(s,hinge)
	var id = str(s)+(" hinge" if hinge.size.x else "")
	ok(layout.mode == expected,id+" mode "+layout.mode)
	ok(is_equal_approx(layout.board.size.x,layout.board.size.y),id+" board square")
	var viewport = Rect2(Vector2.ZERO,layout.size).grow(.1)
	for key in ["hero_player","hero_opponent"]:
		ok(viewport.encloses(layout[key]),id+" corner in view "+key)
		ok(not layout[key].intersects(layout.board),id+" corner never overlaps board "+key)
		if hinge.size.x: ok(not layout[key].intersects(layout.hinge),id+" corner hinge safe "+key)
	var rects = L.major_rects(layout)
	for key in rects:
		ok(viewport.encloses(rects[key]),id+" inside "+key+" "+str(rects[key]))
		for other in rects:
			if key < other: ok(not rects[key].intersects(rects[other]),id+" overlap "+key+" / "+other)
	ok(layout.controls.size.y >= 44 and layout.header.size.y >= 44,id+" 44px control targets")
	ok(not layout.board.intersects(layout.hinge) or hinge.size.x == 0,id+" hinge safe board")
	if hinge.size.x:
		for key in rects: ok(not rects[key].intersects(layout.hinge),id+" hinge safe "+key)

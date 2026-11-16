extends SceneTree
const Backdrop = preload("res://characters/arena_backdrop.gd")
var checks = 0
var failures = 0
func ok(value: bool, message: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",message)
func _initialize():
	for size in [Vector2(320,568),Vector2(390,844),Vector2(568,320),Vector2(867,553),Vector2(669,787),Vector2(1280,720),Vector2(1920,1080)]:
		var g = Backdrop.layout(size)
		var viewport = Rect2(Vector2.ZERO,size)
		ok(viewport.encloses(g.panel),"burst copy panel fits " + str(size))
		ok(viewport.encloses(g.skip),"skip fits " + str(size))
		ok(not g.panel.intersects(g.skip),"copy and skip separate " + str(size))
		ok(g.panel.size.x >= 280 and g.panel.size.y >= 150,"headline usable dimensions " + str(size))
	print("NINEWEAVE_COMIC_PRELUDE ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

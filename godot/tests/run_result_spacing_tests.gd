extends SceneTree
const Cinema = preload("res://characters/cinematic.gd")
var checks = 0
var failures = 0
func ok(value: bool, label: String):
 checks += 1
 if not value: failures += 1; print("FAIL ",label)
func _initialize():
 for size in [Vector2(320,568),Vector2(390,844),Vector2(568,320),Vector2(844,390),Vector2(867,553),Vector2(669,787),Vector2(1280,720),Vector2(1920,1080)]:
  var g = Cinema.combined_geometry(size)
  var order = ["name","names","outcome","score","detail"]
  for i in range(order.size()-1):
   ok(g[order[i]].end.y+4 <= g[order[i+1]].position.y,"spacing "+order[i]+str(size))
  ok(g.detail.end.y+8 <= g.again.position.y,"buttons clear copy "+str(size))
  ok(g.names.size.y >= 12,"name lane readable "+str(size))
 print("NINEWEAVE_RESULT_SPACING ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
 quit(0 if failures == 0 else 1)

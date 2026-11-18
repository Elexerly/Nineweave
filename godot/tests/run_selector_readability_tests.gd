extends SceneTree
const Select = preload("res://characters/select.gd")
const R = preload("res://characters/roster.gd")
var checks = 0
var failures = 0
func ok(value: bool, message: String):
 checks += 1
 if not value: failures += 1; print("FAIL ",message)
func _initialize(): run.call_deferred()
func run():
 for s in [Vector2(867,553),Vector2(669,787),Vector2(1024,720),Vector2(1280,720),Vector2(1920,1080)]:
  var g = Select.geometry(s)
  ok(g.paged and g.per_page == 16 and g.columns == 4 and g.rows == 4,"Duo 4x4 " + str(s))
  for tile in g.tiles:
   ok(tile.size.x >= 88,"large Duo portrait width " + str(s))
   ok(g.grid.encloses(tile) and not tile.intersects(g.nav) and not tile.intersects(g.field),"tiles stay inside grid " + str(s))
 for s in [Vector2(867,553),Vector2(669,787)]:
  var seam = Rect2(s.x*.5-11,0,22,s.y)
  var g = Select.geometry(s,seam)
  ok(g.columns == 4 and g.per_page == 16,"hinge keeps 4x4")
  for tile in g.tiles: ok(not tile.intersects(seam) and tile.size.x >= 44 and tile.size.y >= 44,"hinge touch safety")
 var ui = Select.new(); ui.size = Vector2(867,553); ui.selected_id = "madame_solstice"; root.add_child(ui)
 var beth = ui.portraits[R.index_of("madame_solstice")]
 ok(beth.caption_lines() == PackedStringArray(["BETH"]),"Beth tile first name")
 ok(R.get_hero(ui.selected_id).name == "Beth Solstice","selected plaque retains full name")
 for page in [1,0,1,0]:
  ui.set_page(page)
  var visible_count = 0
  for tile in ui.portraits:
   if tile.visible: visible_count += 1
   ok(tile.visible == (int(tile.index / 16) == page),"page visibility matches hero")
   ok(tile.rig.size.y == tile.size.y-tile.caption_height(),"page switch preserves correct portrait caption band")
  ok(visible_count == 16,"exactly 16 tiles visible")
  ok(beth.caption_lines() == PackedStringArray(["BETH"]),"Beth label stable across paging")
 ui.focus_hero(R.DATA[20].id)
 ui.set_page(1)
 ok(ui.selected_id == R.DATA[20].id and ui.portraits[20].selected,"selected hero retained across pagination")
 ok(ui.paging_controls.size() == 4 and ui.paging_controls[0].visible and ui.paging_controls[1].visible,"arrows and page dots remain visible")
 ui.swipe(Vector2(100,0)); ok(ui.page == 0,"swipe goes to previous page")
 ui.swipe(Vector2(-100,0)); ok(ui.page == 1,"swipe goes to next page")
 var james = ui.portraits[R.index_of("james_ii")]
 ok(james.caption_height() == 18 and james.rig.size.y == james.size.y-18,"Sevryn single-line caption not overlapped")
 ui.free()
 var phone = Select.new(); phone.size = Vector2(390,844); phone.selected_id = R.DATA[20].id; root.add_child(phone)
 ok(phone.geo.per_page == 8 and phone.geo.pages == 4 and phone.page == 2,"narrow phone eight per page opens selected hero page")
 ok(phone.portraits[20].visible and phone.portraits[20].selected,"selected phone hero visible")
 phone.swipe(Vector2(-100,0)); ok(phone.page == 3,"phone swipe navigation")
 ok(phone.paging_controls.size() == 6,"phone retains arrows and four dots")
 phone.free()
 print("NINEWEAVE_SELECTOR_READABILITY ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
 quit(0 if failures == 0 else 1)

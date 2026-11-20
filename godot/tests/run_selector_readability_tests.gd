extends SceneTree
const Select = preload("res://characters/select.gd")
const R = preload("res://characters/roster.gd")
var checks := 0
var failures := 0
func ok(value: bool, message: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",message)
func _initialize(): run.call_deferred()
func touch(at: Vector2, pressed: bool, canceled: bool = false):
	var e := InputEventScreenTouch.new(); e.index = 2; e.position = at; e.pressed = pressed; e.canceled = canceled
	root.push_input(e,true)
func drag(at: Vector2):
	var e := InputEventScreenDrag.new(); e.index = 2; e.position = at
	root.push_input(e,true)
func mouse(at: Vector2, which: int, pressed: bool, emulated: bool = false):
	var e := InputEventMouseButton.new(); e.button_index = which; e.position = at; e.pressed = pressed
	if emulated: e.device = InputEvent.DEVICE_ID_EMULATION
	root.push_input(e,true)
func tile_center(ui, index: int) -> Vector2:
	return ui.geo.tiles[index].get_center()-Vector2(0,ui.scroll_offset)
func run():
	for size in [Vector2(390,844),Vector2(867,553),Vector2(669,787),Vector2(1280,720)]:
		var g = Select.geometry(size,Rect2(),121)
		ok(g.columns == 4 and g.tiles.size() == 121 and g.rows == 31,"arbitrary-size roster layout "+str(size))
		ok(g.scroll_max > 0 and not g.grid.intersects(g.field) and not g.grid.intersects(g.confirm),"viewport clear of controls")
		ok(g.tiles[120].end.y-g.scroll_max <= g.grid.end.y,"last row can fully enter viewport")
	var seam = Rect2(422,0,22,553)
	var folded = Select.geometry(Vector2(867,553),seam)
	for tile in folded.tiles: ok(not tile.intersects(seam) and tile.size.x >= 44 and tile.size.y >= 44,"hinge and target safety")
	var ui = Select.new()
	ui.size = Vector2(390,844); ui.selected_id = R.DATA[20].id
	ui.unlocked_heroes = ["nick"]; ui.blocked_id = R.DATA[1].id
	root.add_child(ui); await process_frame
	ok(ui.portraits[20].visible and ui.portraits[20].selected and ui.scroll_offset > 0,"initial selected hero in view")
	ok(ui.visible_indices.has(R.index_of("nick")) and not ui.visible_indices.has(R.index_of("professor_gilt")),"locked hidden and unlocked present")
	ui._set_scroll(0)
	var first = tile_center(ui,4); var saved = ui.selected_id
	touch(first,true); mouse(first,MOUSE_BUTTON_LEFT,true,true)
	drag(first-Vector2(0,118)); touch(first-Vector2(0,118),false); mouse(first-Vector2(0,118),MOUSE_BUTTON_LEFT,false,true)
	ok(is_equal_approx(ui.scroll_offset,118) and ui.selected_id == saved,"real touch events drag continuously and never select, including emulated mouse")
	# A swipe stops on a partial portrait, not a page or row boundary. Test
	# arbitrary positions before lifting as well as across the next frame.
	ui._set_scroll(0)
	var tracking_at = tile_center(ui,4)
	var top_card = ui.portraits[0]
	var half_card: float = top_card.size.y/2.0
	touch(tracking_at,true)
	for displacement in [17.25,31.5,half_card]:
		drag(tracking_at-Vector2(0,displacement))
		ok(is_equal_approx(ui.scroll_offset,displacement) and is_equal_approx(ui.grid_content.position.y,-displacement),"portrait follows finger during drag at offset "+str(displacement))
		await process_frame
		ok(is_equal_approx(ui.scroll_offset,displacement),"offset stable while finger rests")
	var clipped_height: float = ui.grid_view.get_global_rect().intersection(top_card.get_global_rect()).size.y
	ok(ui.grid_view.clip_contents and top_card.visible and is_equal_approx(clipped_height,half_card),"half a portrait is visibly clipped mid-drag")
	touch(tracking_at-Vector2(0,half_card),false)
	await process_frame; await process_frame
	clipped_height = ui.grid_view.get_global_rect().intersection(top_card.get_global_rect()).size.y
	ok(is_equal_approx(ui.scroll_offset,half_card) and is_equal_approx(clipped_height,half_card) and ui.selected_id == saved,"release keeps exact half-card offset without snap or selection")
	ui._set_scroll(0)
	var at = tile_center(ui,5)
	touch(at,true); drag(at+Vector2(30,0)); drag(at); touch(at,false)
	ok(ui.selected_id == saved and is_zero_approx(ui.scroll_offset),"gesture exceeding slop never selects even if it ends at origin")
	touch(at,true); touch(at,false,true)
	ok(ui.selected_id == saved,"canceled touch does not select")
	touch(at,true); ok(ui.selected_id == saved,"press does not select")
	touch(at,false); ok(ui.selected_id == R.DATA[5].id,"clean tap selects")
	var blocked = tile_center(ui,1)
	touch(blocked,true); touch(blocked,false)
	ok(ui.selected_id == R.DATA[5].id,"blocked current multiplayer hero cannot be selected")
	var pick = tile_center(ui,6)
	mouse(pick,MOUSE_BUTTON_LEFT,true); mouse(pick,MOUSE_BUTTON_LEFT,false)
	ok(ui.selected_id == R.DATA[6].id,"desktop click selects")
	ui._set_scroll(0)
	var wheel = ui.geo.grid.get_center()
	mouse(wheel,MOUSE_BUTTON_WHEEL_DOWN,true)
	ok(ui.scroll_offset > 0 and ui.selected_id == R.DATA[6].id,"desktop wheel changes viewport only")
	ui._set_scroll(0); ui.portraits[6].grab_focus()
	var key := InputEventKey.new(); key.keycode = KEY_DOWN; key.pressed = true
	root.push_input(key,true)
	ok(ui.selected_id == R.DATA[10].id and ui.portraits[10].has_focus() and ui.scroll_offset > 0,"arrow navigation reveals next row and selects")
	var pad := InputEventJoypadButton.new(); pad.button_index = JOY_BUTTON_DPAD_RIGHT; pad.pressed = true
	root.push_input(pad,true)
	ok(ui.selected_id == R.DATA[11].id and ui.portraits[11].has_focus(),"gamepad navigates through same grid")
	var before = ui.scroll_offset
	var outside: Vector2 = ui.geo.hero.get_center()
	touch(outside,true); drag(wheel); touch(wheel,false)
	ok(ui.scroll_offset == before and ui.selected_id == R.DATA[11].id,"gesture started outside grid cannot scroll or select")
	ui.reveal_hero("nick")
	var nick: int = ui.visible_indices.find(R.index_of("nick"))
	at = tile_center(ui,nick)
	touch(at,true); touch(at,false)
	ok(ui.selected_id == "nick" and ui.portraits[nick].selected,"last unlocked hero selectable")
	var beth = ui.portraits[ui.visible_indices.find(R.index_of("madame_solstice"))]
	ok(beth.caption_lines() == PackedStringArray(["BETH"]) and R.get_hero("madame_solstice").name == "Beth Solstice","Beth label and plaque retained")
	ui.free()
	print("NINEWEAVE_SELECTOR_READABILITY ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

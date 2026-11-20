extends SceneTree
const Cinema = preload("res://characters/cinematic.gd")
var checks := 0
var failures := 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize():
	var cinema = Cinema.new()
	for size in [Vector2(320,568),Vector2(390,844),Vector2(1081,1536),Vector2(1536,1081),Vector2(568,320),Vector2(844,390),Vector2(867,553),Vector2(669,787),Vector2(1280,720),Vector2(1920,1080)]:
		var g = Cinema.combined_geometry(size)
		for row in [g.again,g.menu]:
			ok(Rect2(Vector2.ZERO,size).encloses(row) and not row.intersects(g.hero),"buttons preserved beside hero "+str(size))
		var decor := Cinema.portrait_result_decor(size,g.core)
		if Cinema.compact_portrait_result(size):
			ok(is_equal_approx(g.hero.size.aspect(),.75),"portrait frame matches video native aspect "+str(size))
			ok(g.core.encloses(g.hero) and g.core.encloses(g.again) and g.core.encloses(g.menu),"portrait hero and controls share compact footprint "+str(size))
			ok(g.core.size.y < size.y*.84 and is_equal_approx(g.core.get_center().y,size.y*.5),"portrait core vertically centered with room outside "+str(size))
			ok(decor.is_empty() == (size.x < 360 or size.y < 650),"omit portrait ornament on small screens")
			if not decor.is_empty():
				ok(decor.castle.size.x == size.x and decor.footer.size.x == size.x,"art spans both outside margins")
				for band in decor.values():
					var uv := Cinema.scenery_uv(band,Vector2(330,104))
					ok(Rect2(0,0,1,1).encloses(uv) and is_equal_approx((uv.size*Vector2(330,104)).aspect(),band.size.aspect()),"scenery crop preserves aspect ratio")
			for area in decor.values():
				ok(not area.intersects(g.core) and Rect2(Vector2.ZERO,size).encloses(area),"portrait art stays outside core "+str(size))
		else:
			ok(decor.is_empty(),"wide composition remains free of portrait decoration")
			ok(g.hero == Rect2(12 if size.x < 700 else 32,64,size.x*.5-(12 if size.x < 700 else 32)*1.5,size.y-128),"wide hero geometry unchanged")
		for info in [["VICTORY","Nightly","bramble_ox","madame_solstice",""],["VICTORY","WWWWWWWWWWWWWWWWWWWWWWWW","shard_jack","ryan_blaze","Opponent ran out of time"],["DEFEAT","TwentyCharacterNameX","ryan_blaze","shard_jack",""],["X WINS","","shard_jack","unknown",""],["DEFEAT","Nobody","unknown","unknown","Connection lost"]]:
			cinema.result_title = info[0]; cinema.winner_name = info[1]
			cinema.winner_id = info[2]; cinema.loser_id = info[3]; cinema.result_detail = info[4]; cinema.result_score = "4 – 0 BOARDS CLAIMED"
			var rows: Array = cinema.result_text_layout(size)
			for i in range(rows.size()):
				var row = rows[i]
				ok(row.rect.end.y <= g.again.position.y-12 and row.rect.position.y >= 48,"rendered copy clears buttons "+str(size))
				ok(is_equal_approx(row.rect.get_center().x,g.name.get_center().x) and row.rect.position.x > size.x*.5,"text centered within own half "+str(size))
				if i > 0: ok(row.rect.position.y >= rows[i-1].rect.end.y+5.99,"font blocks do not overlap "+str(size))
				for line in row.lines:
					ok(Cinema.P.text_width(line,row.font_size,row.font) <= row.rect.size.x-6,"rendered width fits "+str(size)+" "+str(line))
				ok(row.line_height >= row.font.get_ascent(row.font_size)+row.font.get_descent(row.font_size)+row.border*2,"glyph and keyline retained")
			ok(rows[0].kind == "heading" and rows[0].lines == [info[0]] and rows[0].font == Cinema.P.DISPLAY,"correct result heading uses title font")
			var matchup := rows.filter(func(row): return row.kind == "matchup")
			ok(matchup.is_empty() if info[2] == "unknown" else not matchup.is_empty(),"unknown heroes do not invent a matchup")
			if info[2] == "bramble_ox" and not matchup.is_empty():
				ok(matchup[0].lines == ["Bramble Ox","defeats","Beth Solstice"],"three centered lines keep full character names")
	var size := Vector2(669,787)
	var hinge := Rect2(318,0,44,787)
	for row in cinema.result_text_layout(size,hinge):
		ok(not row.rect.intersects(hinge),"result text safe of hinge")
	ok(not ProjectSettings.get_setting("application/boot_splash/show_image"),"Godot boot logo disabled")
	ok(ProjectSettings.get_setting("application/boot_splash/bg_color").to_html(false) == "080d1b","boot veil matches thank-you navy")
	ok(ProjectSettings.get_setting("application/config/name") == "Nineweave","internal app identity and save location preserved")
	cinema.free()
	print("NINEWEAVE_RESULT_SPACING ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

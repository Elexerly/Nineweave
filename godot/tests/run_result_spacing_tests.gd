extends SceneTree
const Cinema = preload("res://characters/cinematic.gd")
var checks := 0
var failures := 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize():
	var cinema = Cinema.new()
	for size in [Vector2(320,568),Vector2(390,844),Vector2(568,320),Vector2(844,390),Vector2(867,553),Vector2(669,787),Vector2(1280,720),Vector2(1920,1080)]:
		var g = Cinema.combined_geometry(size)
		for row in [g.again,g.menu]:
			ok(Rect2(Vector2.ZERO,size).encloses(row) and not row.intersects(g.hero),"buttons preserved beside hero "+str(size))
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
				ok(" ".join(matchup[0].lines) == "Bramble Ox defeats Beth Solstice","concise winner and loser names")
	var size := Vector2(669,787)
	var hinge := Rect2(318,0,44,787)
	for row in cinema.result_text_layout(size,hinge):
		ok(not row.rect.intersects(hinge),"result text safe of hinge")
	cinema.free()
	print("NINEWEAVE_RESULT_SPACING ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

extends RefCounted
## Local contrast behind online copy; the arena art stays visible outside the lane.
static func draw_panel(node: CanvasItem, rect: Rect2):
	if not rect.has_area(): return
	var steps = 48
	for i in range(steps):
		var t = float(i)/steps
		var alpha = .92 if t < .78 else lerpf(.92,0.0,(t-.78)/.22)
		node.draw_rect(Rect2(rect.position+Vector2(rect.size.x*t,0),Vector2(rect.size.x/steps+1,rect.size.y)),Color(.075,.085,.105,alpha))

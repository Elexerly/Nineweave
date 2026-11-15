extends Button
const Cinema = preload("res://characters/cinematic.gd")
const P = preload("res://ui/paint.gd")
var caption: String = ""
var accent: bool = false
func _ready():
	for state in ["normal","hover","pressed","focus","disabled"]: add_theme_stylebox_override(state,StyleBoxEmpty.new())
func _draw():
	var r = Rect2(Vector2(7,2),size-Vector2(14,4))
	var edge = P.GOLD if accent else P.BLUE
	var skew = 10.0
	var points = PackedVector2Array([r.position+Vector2(skew,0),Vector2(r.end.x,r.position.y),r.end-Vector2(skew,0),Vector2(r.position.x,r.end.y)])
	draw_colored_polygon(points,Color("20354a") if is_hovered() else Color("091224"))
	draw_polyline(points+PackedVector2Array([points[0]]),edge,2.5,true)
	Cinema.headline(self,caption,r.grow(-7),edge,int(clampf(size.y*.54,24,48)))

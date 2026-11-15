extends Control
const P = preload("res://ui/paint.gd")
const KNIGHT = preload("res://assets/art/crystal_knight.png")
const GODDESS = preload("res://assets/art/gold_goddess.png")
const CASTLE = preload("res://assets/art/distant_castle.png")
const SKY = preload("res://assets/art/sky_plate.png")
const CRYSTALS = preload("res://assets/art/crystal_cluster.png")
var clock: float = 0
var reduced_motion: bool = false
var title_mode: bool = true
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	var rays = ColorRect.new(); rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat = ShaderMaterial.new(); mat.shader = preload("res://assets/shaders/aurora.gdshader")
	rays.material = mat; add_child(rays)
	var motes = CPUParticles2D.new()
	motes.name = "AmbientMotes"; motes.amount = 24; motes.lifetime = 12
	motes.direction = Vector2(0,-1); motes.spread = 22
	motes.initial_velocity_min = 3; motes.initial_velocity_max = 9
	motes.gravity = Vector2.ZERO; motes.scale_amount_min = .5; motes.scale_amount_max = 1.6
	motes.color = Color(.65,.85,1,.42); motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	add_child(motes)
func _process(delta):
	clock += delta*(.1 if reduced_motion else 1.0)
	var motes = get_node_or_null("AmbientMotes")
	if motes:
		motes.position = Vector2(size.x*.5,size.y*.6)
		motes.emission_rect_extents = size*.48
		motes.amount = 8 if reduced_motion else 24
	queue_redraw()
func _draw():
	draw_rect(Rect2(Vector2.ZERO,size),Color("020917"))
	draw_texture_rect(SKY,Rect2(Vector2.ZERO,size),false,Color(.24,.4,.64,.52))
	# Drifting, low-contrast cloud banks; cheap translucent polygon layers.
	for k in range(7):
		var points = PackedVector2Array()
		var cy = size.y*(.3+k*.095)
		points.append(Vector2(0,size.y))
		for i in range(31):
			var x = size.x*i/30.0
			points.append(Vector2(x,cy+sin(i*.63+k*1.7+clock*.025)*21+sin(i*1.4+k)*8))
		points.append(Vector2(size.x,size.y))
		if size.x > 1 and size.y > 1:
			for j in range(1,points.size()-2):
				var a = points[j]; var b = points[j+1]
				a.y = minf(a.y,size.y-1); b.y = minf(b.y,size.y-1)
				draw_colored_polygon(PackedVector2Array([a,b,Vector2(b.x,size.y),Vector2(a.x,size.y)]),Color(.11,.25,.43,.035))
	var landscape = size.x > size.y
	var statue_h = size.y*(.82 if title_mode else .63)
	var statue_y = size.y*.05
	var left_width = statue_h*KNIGHT.get_width()/KNIGHT.get_height()
	var right_width = statue_h*GODDESS.get_width()/GODDESS.get_height()
	var art_alpha = .92 if title_mode else .19
	draw_texture_rect(KNIGHT,Rect2(-left_width*.24,statue_y+sin(clock*.15)*3,left_width,statue_h),false,Color(1,1,1,art_alpha))
	draw_texture_rect(GODDESS,Rect2(size.x-right_width*.76,statue_y-sin(clock*.13)*3,right_width,statue_h),false,Color(1,1,1,art_alpha))
	var cw = minf(size.x*.8,size.y*.94)
	draw_texture_rect(CASTLE,Rect2((size.x-cw)/2,size.y*(.32 if title_mode else .72),cw,cw*.267),false,Color(.75,.88,1,.75 if title_mode else .2))
	# Ancient pillars in silhouette, back-lit rims.
	for side in [0,1]:
		var x = size.x*(.035 if side == 0 else .95)
		var py = size.y*.57
		draw_rect(Rect2(x,py,12,size.y-py),Color(.04,.065,.1,.8))
		draw_line(Vector2(x+12,py),Vector2(x+12,size.y),Color(.67,.42,.12,.16),2)
		draw_rect(Rect2(x-5,py-7,22,8),Color(.3,.25,.18,.45))
	# Foreground floating crystal shards with faceted geometry.
	for i in range(12):
		var side = -1 if i%2 == 0 else 1
		var x = 10+i%3*13 if side < 0 else size.x-12-i%3*14
		var y = size.y*.7+i%5*size.y*.075+sin(clock*.3+i)*4
		P.crystal(self,Vector2(x,y),25+i%4*11,Color(.05,.45,.8,.75),side*(.25+i%3*.2))
	if landscape:
		draw_texture_rect(CRYSTALS,Rect2(size.x-94,size.y-216,94,210),false,Color(.7,.85,1,.7))
	for i in range(65):
		var x = fmod(i*97.37+23,size.x)
		var y = fmod(i*157.73+clock*(1+i%3)*.7,size.y)
		var alpha = (.3+.7*pow(sin(clock*.5+i*1.9),2))*.4
		var col = Color(.75,.85,1,alpha) if i%3 else Color(1,.76,.35,alpha)
		draw_circle(Vector2(x,y),.5+(i%3)*.4,col)
		if i%8 == 0:
			draw_line(Vector2(x-3,y),Vector2(x+3,y),Color(col,alpha*.45),.7,true)
			draw_line(Vector2(x,y-3),Vector2(x,y+3),Color(col,alpha*.45),.7,true)

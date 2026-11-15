extends Control
## Layered night-sky backdrop. Own _draw: full-viewport gradient + soft sky plate (covers the
## whole viewport at every size). Child 1: shader clouds + warm light rays. Child 2: art layer
## with the floating castle, the two flanking statues (never upscaled beyond ~1.5x),
## crystal clusters, faint ruins, sparkles. Gentle parallax; cheap enough for phones.
const P = preload("res://ui/paint.gd")
const KNIGHT = preload("res://assets/art/crystal_knight.png")
const GODDESS = preload("res://assets/art/gold_goddess.png")
const CASTLE = preload("res://assets/art/distant_castle.png")
const SKY = preload("res://assets/art/sky_plate.png")
const CRYSTALS = preload("res://assets/art/crystal_cluster.png")
const CRYSTALS_LEFT = preload("res://assets/art/crystal_cluster_left.png")
const RUINS = preload("res://assets/art/ruins.png")
const MAX_ART_SCALE = 1.5

class Layer extends Control:
	var painter: Callable
	func _draw():
		if painter.is_valid(): painter.call(self)

var background_theme: String = "crystal"
var clock: float = 0
var reduced_motion: bool = false
var title_mode: bool = true
## Where the title sits (logical px); rays fan from here and the castle floats beneath it.
var title_anchor: Vector2 = Vector2(-1,-1)
## Region the title composition should use (left of a hinge, or the full screen).
var title_region: Rect2 = Rect2()
## Winning side's statue glows (1 knight/X, 2 goddess/O) with strength 0..1.
var win_player: int = 0
var win_glow: float = 0
var _sky_mat: ShaderMaterial
var art: Layer
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	var rays = ColorRect.new(); rays.name = "Sky"; rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_mat = ShaderMaterial.new(); _sky_mat.shader = preload("res://assets/shaders/aurora.gdshader")
	rays.material = _sky_mat; add_child(rays)
	art = Layer.new(); art.name = "Art"; art.painter = _draw_art
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE; art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(art)
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
	refresh()
func refresh():
	var sky_node = get_node_or_null("Sky")
	if sky_node: sky_node.visible = background_theme == "crystal"
	if _sky_mat:
		var anchor = _anchor()
		_sky_mat.set_shader_parameter("ray_center",Vector2(anchor.x/maxf(1,size.x),anchor.y/maxf(1,size.y)))
		_sky_mat.set_shader_parameter("ray_strength",.95 if title_mode else (.22+win_glow*.5))
		_sky_mat.set_shader_parameter("ray_color",Vector3(1,.78,.38) if title_mode or win_player != 1 else Vector3(.35,.8,1))
		_sky_mat.set_shader_parameter("cloud_strength",.55 if title_mode else .42)
		_sky_mat.set_shader_parameter("aspect",size.x/maxf(1,size.y))
		_sky_mat.set_shader_parameter("motion",0.0 if reduced_motion else 1.0)
	queue_redraw()
	if art: art.queue_redraw()
func _anchor() -> Vector2:
	if title_mode and title_anchor.x >= 0: return title_anchor
	return Vector2(size.x*.5,size.y*(.22 if title_mode else .45))
func _draw():
	var w = size.x; var h = size.y
	if w < 1 or h < 1: return
	if background_theme != "crystal":
		var top_theme = Color("0c2236") if background_theme == "tidal" else Color("372c4c")
		var low_theme = Color("235869") if background_theme == "tidal" else Color("94654f")
		draw_polygon(PackedVector2Array([Vector2.ZERO,Vector2(w,0),Vector2(w,h),Vector2(0,h)]),PackedColorArray([top_theme,top_theme,low_theme,low_theme]))
		return
	var top = Color("030a1d"); var mid = Color("0a2048"); var low = Color("061330")
	draw_polygon(PackedVector2Array([Vector2(0,0),Vector2(w,0),Vector2(w,h*.55),Vector2(0,h*.55)]),PackedColorArray([top,top,mid,mid]))
	draw_polygon(PackedVector2Array([Vector2(0,h*.55),Vector2(w,h*.55),Vector2(w,h),Vector2(0,h)]),PackedColorArray([mid,mid,low,low]))
	draw_texture_rect(SKY,Rect2(Vector2.ZERO,size),false,Color(.35,.5,.8,.38))
func _art_scale(target_height: float, tex: Texture2D) -> float:
	return minf(MAX_ART_SCALE,target_height/tex.get_height())
func _draw_art(n: Control):
	var w = size.x; var h = size.y
	if w < 1 or h < 1: return
	if background_theme != "crystal": _draw_local_theme(n); return
	var region = title_region if title_region.size.x > 0 else Rect2(Vector2.ZERO,size)
	var anchor = _anchor()
	var landscape = region.size.x > region.size.y
	var drift = 0.0 if reduced_motion else 1.0
	# Distant floating castle beneath the title (title) or low on the horizon (game).
	var cs: float
	var castle_center: Vector2
	if title_mode:
		cs = minf(MAX_ART_SCALE,(region.size.x*(.92 if not landscape else .5))/CASTLE.get_width())
		castle_center = Vector2(anchor.x,anchor.y+(h*.16 if not landscape else h*.24))
	else:
		cs = minf(MAX_ART_SCALE,w*.6/CASTLE.get_width())
		castle_center = Vector2(w*.5,h*.62)
	var csz = CASTLE.get_size()*cs
	var cpos = castle_center-csz*.5+Vector2(sin(clock*.07)*6,sin(clock*.11)*3)*drift
	P.halo_rect(n,Rect2(cpos-csz*Vector2(.1,.3),csz*Vector2(1.2,1.6)),Color(.25,.55,1,.22 if title_mode else .1))
	n.draw_texture_rect(CASTLE,Rect2(cpos,csz),false,Color(1,1,1,.95 if title_mode else .3))
	# Faint ruins on both flanks (in-game), mirrored on the left.
	if not title_mode:
		var rs = minf(MAX_ART_SCALE,h*.42/RUINS.get_height())
		var rsz = RUINS.get_size()*rs
		var ry = h*.78-rsz.y
		n.draw_texture_rect(RUINS,Rect2(Vector2(w-rsz.x*.92,ry),rsz),false,Color(.7,.8,1,.28))
		n.draw_set_transform(Vector2(rsz.x*.92,0),0,Vector2(-1,1))
		n.draw_texture_rect(RUINS,Rect2(Vector2(0,ry),rsz),false,Color(.7,.8,1,.28))
		n.draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
	# Flanking statues: crystal knight left, gold goddess right.
	var th = (h*(.44 if not landscape else .8)) if title_mode else h*.55
	var ks = _art_scale(th,KNIGHT); var gs = _art_scale(th,GODDESS)
	var ksz = KNIGHT.get_size()*ks; var gsz = GODDESS.get_size()*gs
	var alpha = 1.0 if title_mode else .2
	var left_x = region.position.x-ksz.x*(.26 if not landscape else .08)
	var right_x = region.end.x-gsz.x*(.74 if not landscape else .9)
	if not title_mode: left_x = -ksz.x*.3; right_x = w-gsz.x*.7
	# The crops' top rows are the reference's top edge (unfeathered), so keep them above y=0.
	var kpos = Vector2(left_x,-4+sin(clock*.15)*3*drift)
	var gpos = Vector2(right_x,-4-sin(clock*.13)*3*drift)
	var k_alpha = alpha+(win_glow*.55 if win_player == 1 else 0.0)
	var g_alpha = alpha+(win_glow*.55 if win_player == 2 else 0.0)
	if win_player == 1 and win_glow > 0: P.halo(n,kpos+ksz*Vector2(.5,.42),ksz.y*.7,Color(.3,.8,1,.55*win_glow))
	if win_player == 2 and win_glow > 0: P.halo(n,gpos+gsz*Vector2(.55,.5),gsz.y*.7,Color(1,.78,.35,.55*win_glow))
	if title_mode:
		P.halo(n,kpos+ksz*Vector2(.4,.5),ksz.y*.55,Color(.2,.6,1,.16))
		P.halo(n,gpos+gsz*Vector2(.6,.5),gsz.y*.55,Color(1,.7,.3,.14))
	n.draw_texture_rect(KNIGHT,Rect2(kpos,ksz),false,Color(1,1,1,minf(1,k_alpha)))
	n.draw_texture_rect(GODDESS,Rect2(gpos,gsz),false,Color(1,1,1,minf(1,g_alpha)))
	# Glowing crystal clusters in the bottom corners.
	var crs = _art_scale(h*.26,CRYSTALS); var crsz = CRYSTALS.get_size()*crs
	var cls = _art_scale(h*.36,CRYSTALS_LEFT); var clsz = CRYSTALS_LEFT.get_size()*cls
	var bob = sin(clock*.3)*3*drift
	var ca = .95 if title_mode else .55
	P.halo(n,Vector2(w-crsz.x*.45,h-crsz.y*.45),crsz.y*.6,Color(.2,.6,1,.22*ca))
	P.halo(n,Vector2(clsz.x*.45,h-clsz.y*.35),clsz.y*.5,Color(.3,.45,1,.2*ca))
	n.draw_texture_rect(CRYSTALS,Rect2(Vector2(w-crsz.x,h-crsz.y+bob),crsz),false,Color(1,1,1,ca))
	n.draw_texture_rect(CRYSTALS_LEFT,Rect2(Vector2(0,h-clsz.y-bob),clsz),false,Color(1,1,1,ca))
	# A few faceted floating shards for depth.
	for i in range(6):
		var side = -1 if i%2 == 0 else 1
		var x = (16+i%3*18) if side < 0 else w-18-i%3*20
		var y = h*(.5+i*.06)+sin(clock*.3+i)*5*drift
		P.halo(n,Vector2(x,y),14+i%3*5,Color(.2,.6,1,.18))
		P.crystal(n,Vector2(x,y),10+i%3*6,Color(.15,.55,.95,.7),side*(.25+i%3*.2))
	# Sparkles / stars.
	for i in range(54):
		var x = fmod(i*97.37+23,w)
		var y = fmod(i*157.73+clock*(1+i%3)*.7*drift,h)
		var a = (.3+.7*pow(sin(clock*.5+i*1.9),2))*.5
		var col = Color(.75,.88,1,a) if i%3 else Color(1,.8,.4,a)
		n.draw_circle(Vector2(x,y),.6+(i%3)*.45,col)
		if i%6 == 0:
			n.draw_line(Vector2(x-4,y),Vector2(x+4,y),Color(col,a*.6),.8,true)
			n.draw_line(Vector2(x,y-4),Vector2(x,y+4),Color(col,a*.6),.8,true)

## Cheap alternate skies, deliberately separate from the original art path.
func _draw_local_theme(n: Control):
	var w = size.x; var h = size.y
	var sun = Vector2(w*.78,h*.26)
	if background_theme == "tidal":
		P.halo(n,sun,minf(w,h)*.2,Color(.7,.9,1,.18))
		n.draw_circle(sun,minf(w,h)*.054,Color("d3e5df"))
		for layer in range(4):
			var points = PackedVector2Array(); var foam = PackedVector2Array()
			for i in range(41):
				var x = w*i/40.0
				var y = h*(.52+layer*.12)+sin(i*.27+clock*.18+layer)*h*.017+sin(i*.51-clock*.12)*h*.008
				points.append(Vector2(x,y)); foam.append(Vector2(x,y))
			points.append(Vector2(w,h)); points.append(Vector2(0,h))
			n.draw_colored_polygon(points,Color("123646").lerp(Color("071626"),layer/4.0))
			n.draw_polyline(foam,Color(.54,.83,.85,.2),1.4,true)
	else:
		P.halo(n,sun,minf(w,h)*.3,Color(1,.62,.32,.25))
		n.draw_circle(sun,minf(w,h)*.085,Color("e1ab76"))
		for layer in range(3):
			var points = PackedVector2Array([Vector2(0,h)])
			var y = h*(.55+layer*.12)
			for i in range(8):
				var x = w*i/7.0; var step = sin(i*7.13+layer*2)*h*.055
				points.append(Vector2(x,y+step)); points.append(Vector2(x+w*.07,y+step))
			points.append(Vector2(w,h))
			n.draw_colored_polygon(points,Color("514154").lerp(Color("172333"),layer/3.0))
	for i in range(18):
		var pos = Vector2(fmod(i*97.37+23,w),fmod(i*157.73+13,h*.4))
		n.draw_circle(pos,.9,Color(.8,.9,1,.35))

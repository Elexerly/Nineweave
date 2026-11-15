extends Control
## Authored vector cutouts: one cached vertex-colour mesh per articulated part.
## The 12 thumbnails are frozen; only focused/field heroes evaluate their rig.
const R = preload("res://characters/roster.gd")
const P = preload("res://ui/paint.gd")
const INK = Color("071426")
static var ART_CACHE: Dictionary = {}
const CLIPS = ["idle","idle_power","idle_stagger","hover_react","lock_in","board_pop","victory","defeat","score_flash","mark_push"]
class Cutout extends Node2D:
	var vertices = PackedVector2Array()
	var colors = PackedColorArray()
	var mesh: ArrayMesh
	var chromatic: bool = false
	func poly(points: PackedVector2Array, color: Color):
		if points.size() < 3: return
		var indices = Geometry2D.triangulate_polygon(points)
		for i in indices: vertices.append(points[i]); colors.append(color)
	func shape(coords: Array, color: Color, shade: bool = true, ink: bool = true):
		var points = PackedVector2Array()
		for i in range(0,coords.size(),2): points.append(Vector2(coords[i],coords[i+1]))
		if ink:
			for outline in Geometry2D.offset_polygon(points,2.1,Geometry2D.JOIN_MITER): poly(outline,Color("071426"))
		poly(points,color)
		if not shade: return
		var rect = Rect2(points[0],Vector2.ZERO)
		for p in points: rect = rect.expand(p)
		var mid = rect.position.x+rect.size.x*.56
		var shadow = PackedVector2Array([Vector2(mid,rect.position.y-1),rect.position+Vector2(rect.size.x+1,-1),rect.end+Vector2.ONE,Vector2(mid,rect.end.y+1)])
		for area in Geometry2D.intersect_polygons(points,shadow): poly(area,color.lerp(Color("101e3e"),.55))
		var lit = PackedVector2Array([rect.position-Vector2.ONE,rect.position+Vector2(rect.size.x+1,-1),rect.position+Vector2(0,rect.size.y*.37)])
		for area in Geometry2D.intersect_polygons(points,lit): poly(area,color.lightened(.23))
	func line(coords: Array, color: Color, width: float = 2.0):
		for i in range(0,coords.size()-2,2):
			var a = Vector2(coords[i],coords[i+1]); var b = Vector2(coords[i+2],coords[i+3]); var n = (b-a).orthogonal().normalized()*width*.5
			poly(PackedVector2Array([a+n,b+n,b-n,a-n]),color)
	func dot(center: Vector2, radius: float, color: Color, sides: int = 12):
		var points = PackedVector2Array()
		for i in range(sides): points.append(center+Vector2.from_angle(i*TAU/sides)*radius)
		poly(points,color)
	func bake():
		if vertices.is_empty(): return
		var arrays = []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_COLOR] = colors
		mesh = ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		vertices = PackedVector2Array(); colors = PackedColorArray(); queue_redraw()
	func _draw():
		if mesh:
			if chromatic:
				draw_mesh(mesh,null,Transform2D(0,Vector2(-1.2,0)),Color(.3,.8,1,.5))
				draw_mesh(mesh,null,Transform2D(0,Vector2(1.2,0)),Color(1,.4,.6,.4))
			draw_mesh(mesh,null)

var hero_id: String = "vesper_vale"
var clip: String = "idle"
var time: float = 0
var clip_age: float = 0
var reduced_motion: bool = false
var frozen: bool = false
var bust: bool = false
var facing: float = 1
var side: int = 1
var bones: Dictionary = {}
var rest: Dictionary = {}
var actor: Node2D
var _mat: ShaderMaterial
var _blend: Dictionary = {}
var _built: bool = false
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE; clip_contents = true
	_mat = ShaderMaterial.new(); _mat.shader = preload("res://assets/shaders/comic.gdshader")
	_build(); resized.connect(_fit)
func configure(id: String, portrait: bool = false):
	var changed = hero_id != id
	hero_id = id; bust = portrait
	if is_inside_tree() and (changed or not _built): _build()
	_fit()
func _part(id: String, at: Vector2, parent: Node2D = null) -> Cutout:
	var part = Cutout.new(); part.name = id; part.position = at; part.material = _mat
	(parent if parent != null else actor).add_child(part); bones[id] = part; rest[id] = at
	return part
func _build():
	if actor:
		remove_child(actor); actor.queue_free()
	bones.clear(); rest.clear(); _blend.clear()
	actor = Node2D.new(); actor.name = "CutoutRig"; add_child(actor)
	if ART_CACHE.has(hero_id):
		for entry in ART_CACHE[hero_id]:
			var parent = bones[entry.parent] if not entry.parent.is_empty() else actor
			var part = _part(entry.id,entry.position,parent); part.mesh = entry.mesh; part.visible = entry.visible
			part.chromatic = bust and entry.id in ["head","cape"] and not reduced_motion
			part.queue_redraw()
		_built = true; _fit(); pose(0); return
	var h = R.get_hero(hero_id); var index = R.index_of(hero_id)
	var col = Color(h.palette[0]); var dark = Color(h.palette[1]); var trim = Color(h.palette[2]); var skin = [Color("c8a6a0"),Color("bb8057"),Color("af93b8"),Color("91b4c8"),Color("d6a078"),Color("92604e"),Color("ac786c"),Color("d6b8af"),Color("967f69"),Color("c7927f"),Color("bda18c"),Color("7cbaaf")][index]
	var heavy = index in [3,8]; var width = 68.0 if heavy else (49.0 if index in [1,7] else 37.0)
	var cape = _part("cape",Vector2(0,153))
	if index == 9:
		cape.shape([-26,0,-102,22,-118,141,-58,102,-18,213,16,102,103,147,83,16,27,0],col)
		cape.line([-96,28,-18,206,78,20],trim,3); cape.line([-112,133,-2,67,96,139],trim,2)
	elif index == 11:
		cape.shape([-31,20,-79,50,-103,197,-47,171,-76,222,26,208,72,162,83,44,28,14],dark)
	else:
		cape.shape([-width+5,0,-width-24,57,-width-36,211,-30,197,-8,222,24,207,width+45,220,width+18,60,width-2,0],dark)
		cape.shape([-width+3,5,-width-16,55,-width-28,190,-width+5,156,-20,32],col.darkened(.25))
		cape.line([-width+2,8,-width-10,82,-width-20,178],trim.darkened(.3),3)
	var hips = _part("hips",Vector2(0,276))
	hips.shape([-34,-5,32,-5,36,34,11,53,-6,35,-29,48,-43,28],dark)
	for sign_value in [-1,1]:
		var label = "left" if sign_value < 0 else "right"
		var leg = _part(label+"_leg",Vector2(sign_value*22,308))
		leg.shape([-16,-10,15,-9,19,48,9,66,-17,62,-23,32],col.darkened(.17))
		leg.shape([-13,1,-3,4,-1,48,-12,54],trim.darkened(.12))
		var boot = _part(label+"_boot",Vector2(0,60),leg)
		boot.shape([-17,-5,12,-7,17,28,29,39,26,49,-23,49,-27,36],dark)
		boot.shape([-19,-3,13,-5,15,5,-18,9],trim)
		boot.line([-19,38,19,38],col.lightened(.15),3)
	if index == 11:
		bones.left_leg.visible = false; bones.right_leg.visible = false
		var tail = _part("tail",Vector2(0,303))
		tail.shape([-34,-10,28,-10,49,38,41,72,11,91,51,99,92,68,91,104,66,132,26,137,-16,114,-38,70,-40,27],col)
		tail.line([-24,15,12,32,21,63,0,82,24,113,57,119,79,101],trim,3)
	var torso = _part("torso",Vector2(0,177))
	torso.shape([-width,-15,-15,-25,17,-25,width,-14,width+9,20,width*.68,63,29,102,-29,102,-width*.7,61,-width-9,18],col)
	torso.shape([-13,-15,14,-15,21,54,6,83,-14,67,-23,16],dark)
	torso.line([-width+3,-10,-20,1,0,29,22,0,width-2,-10],trim,5)
	# Waist clasp, piping and shadow-only halftone. These are cached into the torso.
	torso.shape([-31,83,30,83,29,96,-30,96],dark)
	torso.shape([-8,82,7,82,13,89,6,97,-8,97,-13,90],trim)
	for i in range(9): torso.dot(Vector2(width*.58+(i%3)*5,24+(i/3)*7),1.2,Color("132544"),6)
	if index == 10:
		torso.shape([-20,16,20,16,21,64,-17,71],Color("7daaa1"))
		for i in range(3):
			var center = Vector2(-6+i*8,34+i%2*18)
			for j in range(8): torso.dot(center+Vector2.from_angle(j*TAU/8)*10,2,trim,6)
			torso.dot(center,6,dark); torso.dot(center,3,trim)
	if heavy:
		for sign_value in [-1,1]:
			var shoulder = _part("pauldron_"+str(sign_value),Vector2(sign_value*width,170))
			shoulder.shape([-25,-16,13,-25,33,-3,31,29,5,39,-29,22],col)
			shoulder.line([-20,-12,10,-20,27,-2],trim,4)
			for j in range(3): shoulder.dot(Vector2(-16+j*15,17),3,trim)
	for sign_value in [-1,1]:
		var label = "left" if sign_value < 0 else "right"
		var arm = _part(label+"_arm",Vector2(sign_value*(width+1),180))
		arm.shape([-15,-11,12,-9,22,25,18,56,-6,64,-22,36],col)
		arm.shape([-13,-3,7,-3,15,11,-9,16],trim)
		var fore = _part(label+"_fore",Vector2(6,57),arm)
		fore.shape([-14,-9,12,-10,18,27,12,48,-13,48,-20,14],dark)
		fore.shape([-17,17,16,13,16,28,-16,34],col)
		fore.shape([-12,43,11,42,17,56,11,70,-4,76,-15,65],skin)
		fore.line([-8,56,-4,65,2,66,4,56,8,65],INK,1.6)
	var neck = _part("neck",Vector2(0,153))
	neck.shape([-14,-15,14,-15,17,17,0,29,-19,14],skin)
	var head = _part("head",Vector2(0,101))
	# Neck/ears/jaw remain anatomical, even beneath the fortress helmet / split mask.
	head.shape([-28,-30,-10,-43,20,-38,32,-17,28,25,11,48,-8,48,-30,24,-34,-7],skin)
	head.shape([-33,-4,-41,-6,-41,12,-30,19],skin)
	head.shape([29,-3,37,-5,37,12,27,19],skin)
	head.shape([6,-17,18,11,9,18,-2,13],skin.darkened(.28),false,false)
	head.line([-16,29,-1,32,16,27],INK,2)
	head.line([-12,34,5,36,12,32],trim.lightened(.3),1.5)
	var eyes = _part("eyes",Vector2(0,-4),head)
	for sign_value in [-1,1]:
		var x = sign_value*15
		eyes.shape([x-10,-2,x+7,-3,x+6,4,x-7,5],Color("e8f1e9"),false)
		eyes.dot(Vector2(x+2,1),3,trim,8); eyes.dot(Vector2(x+2,1),1.5,INK,8)
		eyes.line([x-10,-10,x+7,-12],INK,3.2)
	# Every head has a separately authored silhouette, not just a palette swap.
	match index:
		0:
			head.shape([-35,-17,-44,-45,-24,-64,5,-68,30,-49,36,-16,18,-34,-5,-29,-22,-12,-25,37,-42,55,-36,10],dark)
			head.shape([-33,-40,-18,-59,4,-61,-11,-44,-29,-29],col)
			head.shape([-4,-61,20,-45,26,-21,11,-31],trim)
		1:
			head.shape([-35,-14,-48,-31,-39,-61,-23,-50,-12,-72,2,-53,22,-67,27,-45,44,-49,40,-19,27,-10,17,-31,-20,-31],col)
			head.shape([-29,-43,-34,-66,-13,-54,0,-78,13,-53,34,-65,27,-41],trim)
			head.shape([-27,20,-15,32,0,25,17,32,28,15,23,44,0,58,-24,44],col)
		2:
			head.shape([-40,28,-48,-29,-28,-63,3,-73,35,-44,43,35,28,56,24,-16,9,-38,-17,-27,-27,51],dark)
			head.line([-36,-28,-19,-49,2,-57,26,-37],trim,3)
			head.shape([-10,-62,0,-81,10,-62,0,-48],col)
		3:
			head.shape([-39,-29,-31,-58,-12,-58,-12,-74,5,-74,5,-57,31,-57,40,-32,37,31,14,49,-19,49,-37,29],col)
			head.shape([-31,-12,31,-12,23,9,-22,9],dark)
			head.line([-25,-2,25,-2],trim,4); head.line([0,10,0,40],trim,3)
		4:
			head.shape([-34,15,-43,-12,-38,-41,-18,-59,-28,-74,-1,-60,23,-65,18,-49,42,-37,27,-14,12,-28,-4,-22,-20,-5,-25,24],dark)
			head.shape([-36,-26,-16,-46,-21,-61,2,-46,23,-49,15,-30,-5,-34],col)
			head.line([-26,-21,-10,-34,15,-34],trim,3)
		5:
			head.shape([-36,31,-40,-32,-26,-56,15,-58,37,-31,34,20,22,39,24,-21,12,-37,-16,-29,-21,36],dark)
			head.shape([-38,-34,-31,-53,29,-53,39,-34],col)
			head.dot(Vector2(0,-48),7,trim); head.line([0,-57,0,-39],INK,2)
		6:
			head.shape([-33,-12,-41,-38,-22,-51,-14,-77,4,-56,28,-71,24,-46,43,-42,25,-14,8,-29,-18,-18],col)
			head.shape([-29,-8,-11,-12,4,-6,24,-15,27,0,6,9,-12,3,-28,8],dark)
			head.line([-25,-1,-9,-3,3,1,22,-5],trim,3)
		7:
			head.shape([-35,-18,-40,-49,-23,-66,0,-46,22,-69,40,-47,34,-13,22,-28,-21,-28],dark)
			head.shape([-31,-25,-4,-37,0,28,-19,38,-32,17],trim)
			head.shape([0,-37,28,-25,32,17,17,38,0,28],Color("a9c4d8"))
			head.line([-26,-2,-10,4,-4,-5],INK,3); head.line([4,-5,13,4,27,-3],INK,3)
			head.shape([-39,-42,-63,-68,-59,-88,-41,-66,-26,-60],trim)
			head.shape([29,-51,44,-65,56,-96,60,-72,51,-47],col)
		8:
			head.shape([-37,-24,-49,-46,-33,-66,-7,-61,21,-65,39,-47,35,-16,21,-29,-19,-25],dark)
			head.shape([-27,-45,-45,-43,-63,-57,-65,-82,-55,-70,-43,-61,-25,-63],trim)
			head.shape([23,-47,43,-44,62,-61,64,-83,53,-68,42,-59,25,-63],trim)
			head.shape([-25,23,23,23,28,37,11,51,-11,51,-30,38],skin.lightened(.1))
			head.dot(Vector2(-16,36),3,INK); head.dot(Vector2(15,36),3,INK)
		9:
			head.shape([-35,7,-39,-33,-21,-61,16,-57,39,-33,26,-1,13,-20,-8,-29,-27,23],dark)
			head.shape([-40,-31,-29,-53,27,-51,40,-29],col)
			for x in [-17,15]:
				head.dot(Vector2(x,-36),13,trim); head.dot(Vector2(x,-36),9,Color("3d6c85")); head.line([x-5,-41,x+4,-38],P.WHITE,2)
		10:
			head.shape([-35,-18,-41,-38,-24,-59,-10,-54,-4,-68,7,-48,28,-55,37,-31,26,-15,16,-32,-8,-27,-25,-3],trim)
			for x in [-17,15]:
				head.dot(Vector2(x,0),13,col); head.dot(Vector2(x,0),10,Color("3d766d")); head.line([x-6,-4,x+4,-7],trim,2)
			head.line([-4,0,2,0],trim,3)
			head.shape([-14,25,-1,30,12,23,19,36,3,46,-14,38,-22,30],trim)
		11:
			head.shape([-35,30,-49,-11,-43,-48,-23,-67,10,-61,34,-40,48,12,37,50,25,19,17,-19,-8,-35,-28,-16,-23,31],dark)
			head.shape([-34,-22,-61,-45,-62,-18,-42,10],col)
			head.shape([28,-22,57,-44,57,-13,38,13],col)
			for i in range(4): head.dot(Vector2(-22+i*14,-36+absf(i-1.5)*4),4,trim)
	# Props are articulated at the hand except large silhouette anchors.
	var prop = _part("prop",Vector2(3,61),bones.right_fore)
	match index:
		0:
			prop.line([0,0,22,-43,30,-91,12,-135,-6,-151],trim,7); prop.line([-6,-151,-10,46,22,36,0,0],col,3)
			prop.line([-10,-145,-10,40],P.WHITE,1.5)
		1:
			prop.line([0,38,0,-133],trim,9); prop.shape([-15,-130,-28,-153,-10,-160,0,-184,13,-160,29,-152,15,-131],col)
			prop.dot(Vector2(0,-151),9,trim)
		2:
			prop.line([-1,0,-60,-45,-89,-27,-62,6,-25,-33,1,0,17,-46],trim,3)
			for i in range(4): prop.dot(Vector2(-62+i*19,-18+sin(i)*20),3,col)
		3:
			prop.shape([-8,30,-13,-120,0,-158,13,-120,8,30],trim)
			prop.shape([-31,5,30,5,30,17,-31,17],col); prop.line([0,16,0,49],dark,12)
		4:
			prop.line([0,24,6,-94],trim,7); prop.shape([-4,-94,-9,-119,5,-149,14,-122,14,-96],col)
			prop.shape([-5,10,-45,3,-46,49,-4,55],trim)
			prop.line([-37,18,-13,22,-35,31,-14,37],dark,2)
		5:
			prop.line([0,37,0,-172],trim,6); prop.shape([-9,-171,0,-199,10,-171],col)
			prop.line([0,-97,31,-90,30,-57],trim,3); prop.shape([17,-61,44,-61,49,-29,40,-18,18,-22,12,-43],dark)
			prop.shape([22,-52,38,-52,41,-30,20,-31],trim); prop.shape([28,-32,24,-39,30,-49,35,-40,33,-33],col)
		6:
			var surf = _part("surf",Vector2(0,423))
			surf.shape([-113,0,-71,-16,81,-20,117,-6,80,11,-66,20],col)
			surf.line([-85,3,0,-5,84,-7],trim,4)
			prop.shape([-10,-7,16,-15,36,-8,32,9,11,13,-9,9],trim)
		7:
			prop.shape([0,0,-31,-20,-53,-66,-30,-91,0,-103,31,-85,44,-48,25,-12],trim)
			for j in range(6): prop.line([0,0,-43+j*16,-66-absf(j-2.5)*4],dark,2)
		8:
			var vine = _part("vines",Vector2(-42,158))
			vine.line([0,0,-29,17,-18,56,-41,91,-23,143,-1,162],trim,6)
			for j in range(5): vine.shape([-25,j*31,-47,j*31-5,-37,j*31+16,-23,j*31+8],col)
			var bird = _part("bird",Vector2(-46,23))
			bird.shape([-14,0,-4,-9,9,-8,16,0,26,3,14,6,6,12,-7,9,-16,15],trim)
		9:
			prop.line([0,0,16,-48,45,-86],trim,2); prop.shape([34,-91,48,-119,66,-95,55,-62],col)
			prop.line([53,-63,61,-41,48,-26,66,-6],trim,3)
		10:
			prop.line([0,-26,11,-36,23,-20,18,1,4,17],trim,2); prop.dot(Vector2(4,27),24,col); prop.dot(Vector2(4,27),19,dark)
			prop.line([4,11,4,27,14,32],trim,3)
		11:
			prop.shape([-10,4,-23,-8,-20,-31,0,-48,27,-41,45,-18,40,2,24,17,3,20],trim)
			prop.line([31,-15,17,-28,0,-23,-9,-8,0,4,15,4,24,-6,15,-15,6,-10],col,4)
	for key in bones:
		bones[key].chromatic = (bust or clip == "lock_in") and key in ["head","cape"]
		bones[key].bake()
	var stored: Array = []
	for key in bones:
		var b = bones[key]
		stored.append({"id":key,"position":rest[key],"parent":str(b.get_parent().name) if b.get_parent() != actor else "","mesh":b.mesh,"visible":b.visible})
	ART_CACHE[hero_id] = stored
	_built = true; _fit(); pose(0)
func _fit():
	if not actor: return
	var s = minf(size.x/(175 if bust else 265),size.y/(185 if bust else 455))
	actor.position = Vector2(size.x*.5,(-30 if bust else 9)*s)
	actor.scale = Vector2(s*facing,s)
func set_clip(value: String):
	if value == clip or not value in CLIPS: return
	_blend.clear()
	for key in bones: _blend[key] = {"rotation":bones[key].rotation,"position":bones[key].position,"scale":bones[key].scale}
	clip = value; clip_age = 0
func _process(delta):
	if frozen: return
	time += delta; clip_age += delta
	pose(time)
func pose(at: float):
	if not _built: return
	time = at
	var phase = at*TAU/5.2
	var motion = .2 if reduced_motion else 1.0
	var breath = sin(phase*2)*motion
	var lean = sin(phase)*.022*motion
	var punch = sin(PI*clampf(clip_age/.7,0,1))
	var stagger = clip == "idle_stagger" or clip == "defeat"
	var power = clip in ["idle_power","victory","score_flash","mark_push"]
	var attack = clip in ["lock_in","board_pop","hover_react","victory","score_flash","mark_push"]
	var blend = smoothstep(0,.22,clip_age)
	var index = R.index_of(hero_id)
	var react = smoothstep(0,.6,clip_age)
	for key in bones:
		var rot = 0.0; var pos: Vector2 = rest[key]; var scl = Vector2.ONE
		if key == "torso":
			pos.y += breath*1.6; scl.y = 1+breath*.007+(0.025 if power else 0.0)
			rot = lean+(.075 if stagger else 0.0)-(.04*punch*motion if attack else 0.0)
		elif key == "head": rot = -lean*.6+(.14 if stagger else -.04 if power else 0.0); pos.y += breath*1.9
		elif key == "cape": rot = sin(phase-.8)*.028*motion; scl.x = 1+sin(phase-.4)*.035*motion
		elif key == "right_arm": rot = -.15+sin(phase-.25)*.025*motion-(.45*punch*motion if attack else 0.0)+(.2 if stagger else 0.0)
		elif key == "left_arm": rot = .16-sin(phase-.4)*.025*motion+(.3*punch*motion if attack else 0.0)
		elif key == "right_fore": rot = -.18-(.3*punch*motion if attack else 0.0)
		elif key == "left_fore": rot = .1+sin(phase-.6)*.04*motion
		elif key == "prop": rot = sin(phase-.7)*.05*motion+(.24*punch*motion if attack else 0.0)
		elif key == "eyes": scl.y = maxf(.1,1-pow(maxf(0,cos(phase)),80)*.9)
		elif key == "bird": pos.y += sin(phase*2)*2*motion
		if clip == "defeat":
			if key in ["hips","torso","head","neck"]: pos.y += (26 if index in [1,3,8,9] else 10)*react
			if key == "head": rot += ([.12,.23,.18,.16,-.15,.25,.2,.35,.14,-.2,.1,.22][index])*react
			if key == "right_arm": rot += (.65 if index in [5,10,11] else .25)*react
			if key == "left_arm": rot -= (.65 if index in [5,10,11] else .2)*react
			if key == "prop": rot += (.6 if index in [4,6,10,11] else -.2)*react
			if key == "cape": scl.x *= 1-react*.13
		if attack:
			if key == "head": rot -= sin(clampf(clip_age/.7,0,1)*PI)*.07*motion
			if key == "prop": rot += sin(clampf((clip_age-.08)/.75,0,1)*PI)*(.2 if index in [0,3,5] else -.15)*motion
		if key == "bird": rot = sin(phase)*.08*motion
		if key == "surf": rot = sin(phase)*.024*motion
		if key == "tail": rot = sin(phase-.5)*.035*motion
		if _blend.has(key):
			rot = lerpf(_blend[key].rotation,rot,blend); pos = _blend[key].position.lerp(pos,blend); scl = _blend[key].scale.lerp(scl,blend)
		bones[key].rotation = rot; bones[key].position = pos; bones[key].scale = scl
		var edge = (bust or clip == "lock_in") and key in ["head","cape"] and not reduced_motion
		if bones[key].chromatic != edge: bones[key].chromatic = edge; bones[key].queue_redraw()
	if clip in ["mark_push","score_flash"]: queue_redraw()
	_mat.set_shader_parameter("rim_color",P.mark_color(side))
	_mat.set_shader_parameter("power",.9 if power else .1)
	_mat.set_shader_parameter("impact",punch if attack and not reduced_motion else 0.0)
	actor.modulate = Color(.72,.78,.9) if stagger else Color.WHITE

func _draw():
	if clip not in ["mark_push","score_flash"] or clip_age > .85: return
	var a = sin(PI*clampf(clip_age/.85,0,1))
	var center = Vector2(size.x*.76,size.y*.2)
	P.mark(self,center,minf(size.x,size.y)*.17,side,a,1.4,true)

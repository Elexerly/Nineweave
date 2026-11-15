extends Control
## Authored vector cutouts: one cached vertex-colour mesh per articulated part.
## The 12 thumbnails are frozen; only focused/field heroes evaluate their rig.
const R = preload("res://characters/roster.gd")
const Reactions = preload("res://characters/reactions.gd")
const P = preload("res://ui/paint.gd")
const INK = Color("071426")
static var ART_CACHE: Dictionary = {}
static var FACE_CACHE: Dictionary = {}
# Upper/lower arms, head, hips, free knee, prop: authored resting gesture per hero.
const STANCES = [
	[-.15,-.3,.24,1.1,-.1,-.08,.16,.45], # Vesper: bow ready, hand at hip
	[-.5,-.7,.3,1.4,.08,-.1,.22,1.2], # Rex: upright sceptre, proud hip
	[-.8,-.9,.5,.85,-.1,.1,.1,1.6], # Nyx: thread drawn taut
	[-.12,-.14,.18,.25,.04,-.06,.09,.26], # Bastion: planted sword
	[-1.0,-.55,.15,1.3,-.16,.12,.26,1.2], # Quill: raised brush
	[-.22,-.36,.2,.7,.1,-.08,.2,.58], # Lumen: lantern held level
	[-.62,.35,-.8,.6,-.18,-.14,.34,.35], # Jack: balancing on glass
	[-1.15,-.5,.75,1.0,.17,.16,.24,.8], # Solstice: fan flourish
	[-.13,-.2,.12,.38,.07,-.07,.12,.3], # Ox: relaxed massive guardian
	[-1.9,.45,.6,.8,-.15,.13,.28,.9], # Kite: windward salute
	[-.5,1.0,.25,-.55,.19,-.12,.17,-.5], # Gilt: inspecting a watch
	[.15,1.05,-.25,-.7,-.13,.08,.12,-1.2] # Siren: conch to the heart
]
const CLIPS = ["idle","idle_power","idle_stagger","hover_react","lock_in","board_pop","victory","defeat","score_flash","mark_push","react_nod","react_smirk","react_startle","react_roll","react_cheer","react_panic","react_pout","react_relief"]
class Cutout extends Node2D:
	var vertices = PackedVector2Array()
	var colors = PackedColorArray()
	var mesh: ArrayMesh
	var chromatic: bool = false
	func poly(points: PackedVector2Array, color: Color):
		if points.size() < 3: return
		var indices = Geometry2D.triangulate_polygon(points)
		for i in indices: vertices.append(points[i]); colors.append(color)
	# Closed Catmull–Rom contours are sampled once, then triangulated/cached.
	# Anatomy uses curves; deliberate crown, blade and crystal points stay sharp.
	static func contour(coords: Array, smooth: bool = false) -> PackedVector2Array:
		var p = PackedVector2Array()
		for i in range(0,coords.size(),2): p.append(Vector2(coords[i],coords[i+1]))
		if not smooth: return p
		var result = PackedVector2Array(); var n = p.size()
		for i in range(n):
			var a = p[(i+n-1)%n]; var b = p[i]; var c = p[(i+1)%n]; var d = p[(i+2)%n]
			for j in range(6):
				var t = j/6.0
				result.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
		return result
	func curve(coords: Array, color: Color, shade: bool = true, ink: bool = true):
		paint_shape(contour(coords,true),color,shade,ink)
	func shape(coords: Array, color: Color, shade: bool = true, ink: bool = true):
		paint_shape(contour(coords),color,shade,ink)
	func paint_shape(points: PackedVector2Array, color: Color, shade: bool, ink: bool):
		if ink:
			for outline in Geometry2D.offset_polygon(points,2.7,Geometry2D.JOIN_ROUND): poly(outline,Color("071426"))
		poly(points,color)
		if not shade: return
		var rect = Rect2(points[0],Vector2.ZERO)
		for p in points: rect = rect.expand(p)
		# Curved, sculpted light masses rather than rectangular/triangular facets.
		var x = rect.position.x; var y = rect.position.y; var w = rect.size.x; var h = rect.size.y
		var shadow = contour([x+w*.66,y-3,x+w*1.1,y-3,x+w*1.1,y+h+3,x+w*.53,y+h+3,x+w*.74,y+h*.65,x+w*.51,y+h*.29],true)
		for area in Geometry2D.intersect_polygons(points,shadow): poly(area,color.lerp(Color("142846"),.62))
		var lit = contour([x-3,y+h*.12,x+w*.24,y-3,x+w*.53,y-3,x+w*.28,y+h*.18,x+w*.2,y+h*.54,x+w*.08,y+h*.7,x-3,y+h*.59],true)
		for area in Geometry2D.intersect_polygons(points,lit): poly(area,color.lightened(.13))
		# Variable-width ink and a narrow curved rim on the light-facing contour.
		if ink:
			for i in range(points.size()):
				var a = points[i]; var b = points[(i+1)%points.size()]
				var n = (b-a).orthogonal().normalized()
				if (a.x+b.x)*.5 < x+w*.23:
					poly(PackedVector2Array([a,b,b-n*1.45,a-n*1.45]),Color(color.lightened(.38),.99))
	func line(coords: Array, color: Color, width: float = 2.0):
		var n_points = coords.size()/2
		for i in range(0,coords.size()-2,2):
			var a = Vector2(coords[i],coords[i+1]); var b = Vector2(coords[i+2],coords[i+3]); var n = (b-a).orthogonal().normalized()*width*.5
			var taper_a = .5 if i == 0 else 1.0; var taper_b = .5 if i/2 == n_points-2 else 1.0
			poly(PackedVector2Array([a+n*taper_a,b+n*taper_b,b-n*taper_b,a-n*taper_a]),color)
			if i > 0: dot(a,width*.48,color,10)
	func dot(center: Vector2, radius: float, color: Color, sides: int = 12):
		var points = PackedVector2Array()
		for i in range(sides): points.append(center+Vector2.from_angle(i*TAU/sides)*radius)
		poly(points,color)
	func bake():
		if vertices.is_empty(): return
		# UV.x is an untextured per-vertex rim flag. Unlike output alpha it is
		# invariant under parent cinematic fades and chromatic draw modulation.
		var tags = PackedVector2Array(); tags.resize(colors.size())
		for i in range(colors.size()):
			if absf(colors[i].a-.99) < .001: tags[i] = Vector2(1,0); colors[i].a = 1
		var arrays = []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = tags
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
var expression: String = ""
var reaction = Reactions.new()
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
		_built = true; expression = ""; _set_expression("neutral"); _fit(); pose(0); return
	var h = R.get_hero(hero_id); var index = R.index_of(hero_id)
	var col = Color(h.palette[0]); var dark = Color(h.palette[1]); var trim = Color(h.palette[2]); var skin = [Color("c8a6a0"),Color("bb8057"),Color("af93b8"),Color("91b4c8"),Color("d6a078"),Color("92604e"),Color("ac786c"),Color("d6b8af"),Color("967f69"),Color("c7927f"),Color("bda18c"),Color("7cbaaf")][index]
	var heavy = index in [3,8]; var width = 72.0 if heavy else (53.0 if index in [1,7] else 42.0)
	var cape = _part("cape",Vector2(-5,153))
	if index == 9:
		cape.curve([-28,0,-92,14,-124,80,-134,151,-73,129,-21,213,17,118,102,147,86,67,32,1],col)
		cape.line([-96,28,-18,206,78,20],trim,3); cape.line([-112,133,-2,67,96,139],trim,2)
	else:
		cape.curve([-width+5,-2,-width-30,26,-width-52,104,-width-65,207,-47,223,-12,202,35,224,width+24,205,width+8,73,width-2,0],dark)
		cape.curve([-width+3,5,-width-21,38,-width-37,108,-width-48,194,-width+2,155,-20,32],col.darkened(.27))
		cape.line([-width+2,8,-width-14,67,-width-27,133,-width-40,181],trim.darkened(.3),2.6)
	var hips = _part("hips",Vector2(0,282))
	hips.curve([-30,-9,31,-8,37,16,23,38,3,42,-21,35,-38,14],dark)
	for sign_value in [-1,1]:
		var label = "left" if sign_value < 0 else "right"
		var leg = _part(label+"_leg",Vector2(sign_value*22,312))
		var thigh = 24.0 if heavy else 18.0
		leg.curve([-thigh,-9,thigh-3,-10,thigh+3,20,thigh-3,53,10,84,-10,88,-thigh-1,60,-thigh-4,23],col.darkened(.13))
		leg.curve([-thigh+4,0,-4,-2,0,25,-8,59,-13,72,-thigh+1,35],col.lightened(.12),false,false)
		leg.line([-thigh+7,26,-thigh+8,46,-9,69],INK,2)
		var boot = _part(label+"_boot",Vector2(0,82),leg)
		boot.curve([-14,-5,12,-7,17,14,12,51,17,70,32,81,33,91,15,96,-23,94,-25,78,-20,45,-21,11],dark)
		boot.curve([-18,-3,14,-5,19,8,10,15,-17,13,-23,7],col)
		boot.line([-17,23,-14,49,-15,72,11,77,25,85],trim.darkened(.12),2.5)
		boot.line([-21,89,1,91,28,89],col.lightened(.25),2.5)
	if index == 11:
		bones.left_leg.visible = false; bones.right_leg.visible = false
		var tail = _part("tail",Vector2(0,303))
		tail.shape([-34,-10,28,-10,49,38,41,72,11,91,51,99,92,68,91,104,66,132,26,137,-16,114,-38,70,-40,27],col)
		tail.line([-24,15,12,32,21,63,0,82,24,113,57,119,79,101],trim,3)
	var torso = _part("torso",Vector2(0,177))
	torso.curve([-width,-12,-21,-24,15,-22,width,-9,width+5,14,width*.66,47,25,86,29,105,-28,103,-29,82,-width*.71,43,-width-5,12],col)
	torso.curve([-12,-17,13,-17,22,23,16,49,6,83,-13,67,-22,16],dark)
	torso.line([-width+9,17,-22,24,-4,40],INK,2.3)
	torso.line([width-7,19,25,29,16,46],INK,2)
	match index:
		0: # Frozen breastplate, flowing collar.
			torso.curve([-36,-12,-18,-18,7,7,26,-14,38,-8,18,22,0,36,-19,13],trim)
			torso.line([-29,0,-16,7,-2,27],col,3)
		1: # Lion heart and a broad heraldic gorget.
			torso.curve([-48,-8,-26,-18,0,-5,25,-18,47,-7,23,11,0,24,-24,12],trim)
			torso.shape([-17,21,0,12,19,22,14,46,0,58,-17,43],trim)
			torso.line([-9,27,-6,37,0,42,7,35,9,26],dark,3)
		2: # Diagonal silk wrap and embroidered filaments.
			torso.curve([-39,-8,-23,-21,28,24,29,48,14,59,-9,22],dark)
			torso.line([-30,-11,-5,13,14,42,16,65],trim,3)
			for j in range(4): torso.line([-10+j*8,4+j*10,0+j*8,3+j*10],col.lightened(.3),1.5)
		3: # Fortress breastplate, layered arched armour.
			torso.curve([-61,3,0,-13,62,5,44,36,0,54,-44,35],dark)
			torso.line([-55,8,0,0,54,9],trim,3.5)
			torso.shape([-11,27,0,19,12,27,11,42,-11,42],trim)
		4: # Cream asymmetric artist lapels and utility strap.
			torso.curve([-34,-14,-16,-21,-8,8,7,31,-3,39,-25,16],trim)
			torso.curve([19,-17,32,-9,16,28,9,32,12,5],dark)
			torso.line([25,-13,-9,78],trim.darkened(.3),4)
		5: # Lantern keeper's teal tabard.
			torso.curve([-24,-17,0,-6,25,-17,18,31,23,71,0,91,-23,72,-16,29],dark)
			torso.line([-22,-11,-10,12,0,21,12,10,22,-11],trim,3)
		6: # Racer's cropped, off-centre jacket and neon piping.
			torso.curve([-39,-9,-18,-20,-9,9,-16,49,-30,65,-39,38],dark)
			torso.line([-33,-8,-23,13,-29,45],trim,3.5)
			torso.line([22,-13,31,8,20,34,10,50],trim,3)
		7: # Split sun/moon stage bodice.
			torso.curve([-42,-8,-20,-21,0,2,-8,45,0,78,-24,65,-35,29],trim)
			torso.curve([0,2,22,-20,42,-8,35,28,23,66,0,78,7,42],Color("a9c4d8"))
		8: # Heavy vine harness.
			torso.line([-56,-6,-31,25,-18,61,0,86,27,53,55,2],trim,5)
			for j in range(3): torso.curve([-18+j*17,22+j*12,-27+j*17,13+j*12,-34+j*17,26+j*12,-23+j*17,34+j*12],col.lightened(.2))
		9: # Sky courier's double-breasted bolero.
			torso.curve([-37,-10,-17,-19,-6,5,4,35,-23,41,-35,22],trim)
			torso.curve([20,-18,35,-8,27,28,13,33,6,8],dark)
			for y in [12,26]: torso.dot(Vector2(-12,y),2.7,col)
		10: # Brass waistcoat and deep turned lapels.
			torso.curve([-32,-12,-14,-23,-4,8,-12,34,-28,16],trim)
			torso.curve([15,-20,34,-9,28,18,9,37,3,11],trim)
		11: # Pearled shell neckline.
			torso.curve([-35,-9,-15,-16,0,-5,16,-17,34,-7,20,17,0,31,-20,17],trim)
			for j in range(7): torso.dot(Vector2(-24+j*8,1+sin(j*PI/6)*15),2.5,Color("f4ece6"),14)
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
			shoulder.curve([-29,-8,-19,-25,10,-28,33,-11,36,17,17,34,-11,32,-31,15],col)
			shoulder.line([-20,-12,10,-20,27,-2],trim,4)
			for j in range(3): shoulder.dot(Vector2(-16+j*15,17),3,trim)
	for sign_value in [-1,1]:
		var label = "left" if sign_value < 0 else "right"
		var arm = _part(label+"_arm",Vector2(sign_value*(width-1),177))
		var muscle = 24.0 if heavy else 16.0
		arm.curve([-muscle,-8,-4,-16,muscle-2,-10,muscle+6,13,muscle+1,35,10,61,-8,64,-muscle-2,42,-muscle-5,17],col)
		arm.curve([-muscle+2,-3,-5,-10,9,-6,13,5,3,10,-muscle+1,12],trim)
		arm.line([-muscle+6,21,-muscle+6,36,-4,49],INK,2.4)
		var fore = _part(label+"_fore",Vector2(2,58),arm)
		fore.curve([-12,-8,9,-10,17,2,17,19,10,45,-9,48,-18,28,-19,9],dark)
		fore.curve([-16,11,16,7,18,20,11,35,-13,39,-19,27],col)
		fore.line([-11,17,11,14],trim,2.5)
		# Curled mitten, four knuckles and a clearly separate folded thumb.
		fore.curve([-10,43,8,42,15,49,15,61,9,70,-3,73,-13,66,-17,57,-16,49],skin)
		fore.curve([-13,48,-19,49,-21,58,-16,63,-10,58,-6,51],skin,false)
		fore.line([-6,51,-7,61,-2,65,3,64,6,54],INK,1.7)
		fore.line([8,52,10,59,8,64],INK,1.3)
	var neck = _part("neck",Vector2(-2,143))
	neck.curve([-10,-15,12,-15,15,12,4,22,-16,10],skin)
	neck.line([-8,-3,-2,8,5,10],skin.darkened(.35),2)
	var head = _part("head",Vector2(-3,101))
	# Sculpted cheek/jaw silhouette, three-quarter bridge and tapered chin.
	head.curve([-28,-28,-12,-41,13,-39,29,-22,29,0,21,28,6,42,-8,42,-27,23,-32,2],skin)
	head.curve([-30,-2,-38,-6,-40,3,-36,14,-28,18],skin)
	head.curve([28,-3,35,-5,36,3,32,15,26,17],skin)
	head.line([-36,1,-33,9,-30,9],skin.darkened(.4),1.8)
	head.curve([5,-13,9,-2,17,10,9,16,0,11],skin.darkened(.32),false,false)
	head.line([-23,17,-19,24,-11,27],skin.darkened(.34),1.7)
	var eyes = _part("eyes",Vector2(0,-4),head)
	_part("pupils",Vector2.ZERO,eyes)
	_part("brows",Vector2(0,-4),head)
	_part("mouth",Vector2.ZERO,head)
	_part("symbols",Vector2.ZERO,head)
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
			var surf = _part("surf",Vector2(0,491))
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
	# Curved hair volume: separate sculpted locks behind the face, silhouette varies by hero.
	if index in [0,2,4,5,9,11]:
		var hair = _part("hair_flow",Vector2(-24,-20),head)
		hair.curve([-5,-19,-23,-25,-38,-3,-35,35,-56,65,-27,56,-9,29,1,-1],dark)
		hair.line([-20,-13,-28,12,-25,32,-40,54],col.darkened(.1),2.4)
		# Hair lies behind the head/face; keep all facial features unobstructed.
		head.move_child(hair,0); hair.show_behind_parent = true
	expression = ""; _set_expression("neutral")
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
	var s = minf(size.x/(150 if bust else 310),size.y/(170 if bust else 520))
	actor.position = Vector2(size.x*.5,(-25 if bust else 13)*s)
	actor.scale = Vector2(s*facing,s)
func set_clip(value: String):
	if value == clip or not value in CLIPS: return
	_blend.clear()
	for key in bones: _blend[key] = {"rotation":bones[key].rotation,"position":bones[key].position,"scale":bones[key].scale}
	clip = value; clip_age = 0
func _process(delta):
	if frozen: return
	time += delta; clip_age += delta; reaction.advance(delta)
	pose(time)
## Per-hero pose tables hoisted out of the per-bone/per-frame loop (Round 3b).
const STANCE_LEAN = [-.085,.055,-.06,.035,-.12,.06,-.14,.09,.045,-.09,.11,-.07]
const DEFEAT_HEAD = [.12,.23,.18,.16,-.15,.25,.2,.35,.14,-.2,.1,.22]
func pose(at: float):
	if not _built: return
	time = at
	var face = "neutral"
	if reaction.remaining > 0: face = Reactions.expression_for(R.index_of(hero_id),reaction.current).id
	elif clip in Reactions.CLIPS: face = Reactions.CLIPS[clip].face
	elif clip in ["victory","score_flash","mark_push"]: face = "celebration"
	elif clip in ["board_pop","hover_react","lock_in","idle_power"]: face = "smug_grin"
	elif clip in ["defeat","idle_stagger"]: face = "sulking"
	_set_expression(face)
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
		# Contrapposto: planted right leg, free left knee, opposing hip/shoulder angles.
		var gesture: Array = STANCES[index]
		var stance: float = STANCE_LEAN[index]
		if key == "hips": rot = gesture[5]; pos.x += 5
		if key == "left_leg": rot = gesture[6]; pos.x -= 7; pos.y -= 3
		if key == "left_boot": rot = -.13
		if key == "right_leg": rot = -.065; pos.x += 6
		if key == "right_boot": rot = .04
		if key == "head": scl = Vector2.ONE*(.9 if bust else .72); pos.x -= 4
		if key == "neck": scl = Vector2(.8,.8)
		if key == "torso":
			pos.y += breath*1.6; scl.y = 1+breath*.007+(0.025 if power else 0.0)
			rot = stance+lean+(.075 if stagger else 0.0)-(.04*punch*motion if attack else 0.0)
		elif key == "head": rot = gesture[4]-lean*.6+(.14 if stagger else -.04 if power else 0.0); pos.y += breath*1.9
		elif key == "cape": rot = -.075+sin(phase-.8)*.028*motion; scl.x = 1+sin(phase-.4)*.035*motion
		elif key == "right_arm": rot = gesture[0]+sin(phase-.25)*.025*motion-(.45*punch*motion if attack else 0.0)+(.2 if stagger else 0.0)
		elif key == "left_arm": rot = gesture[2]-sin(phase-.4)*.025*motion+(.3*punch*motion if attack else 0.0)
		elif key == "right_fore": rot = gesture[1]-(.3*punch*motion if attack else 0.0)
		elif key == "left_fore": rot = gesture[3]+sin(phase-.6)*.04*motion
		elif key == "prop": rot = gesture[7]+sin(phase-.7)*.05*motion+(.24*punch*motion if attack else 0.0)
		elif key == "eyes": scl.y = maxf(.1,1-pow(maxf(0,cos(phase)),80)*.9)
		elif key == "hair_flow": rot = sin(phase-.9)*.05*motion
		elif key == "bird": pos.y += sin(phase*2)*2*motion
		if clip == "defeat":
			if key in ["hips","torso","head","neck"]: pos.y += (26 if index in [1,3,8,9] else 10)*react
			if key == "head": rot += DEFEAT_HEAD[index]*react
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
		# Eased short acting beats layered on the authored resting gesture.
		if clip in Reactions.CLIPS:
			var duration = float(Reactions.CLIPS[clip].duration)
			var t = clampf(clip_age/duration,0,1); var beat = sin(PI*t)
			var react_motion = 0.0 if reduced_motion else 1.0
			match clip:
				"react_nod":
					if key == "head": rot += sin(t*TAU)*.13*react_motion
				"react_smirk","react_relief":
					if key == "head": rot -= beat*.14*react_motion
					if key == "torso": pos.y -= beat*3*react_motion
				"react_startle":
					if key == "head": rot += sin(t*TAU*1.5)*beat*.3*react_motion; pos.x += beat*5*react_motion
					if key == "torso": rot += beat*.06*react_motion
				"react_roll":
					if key == "head": rot += beat*.17*react_motion
					if key in ["left_arm","right_arm"]: pos.y -= beat*4*react_motion
				"react_cheer":
					if key == "left_arm": rot += beat*.7*react_motion
					if key == "left_fore": rot += beat*.5*react_motion
					if key in ["torso","head"]: pos.y -= beat*7*react_motion
				"react_panic":
					if key == "head": rot += sin(t*TAU*3)*beat*.13*react_motion
					if key == "left_arm": rot += beat*.35*react_motion
				"react_pout":
					if key == "head": rot += beat*.25*react_motion; pos.y += beat*3*react_motion
					if key == "torso": scl.y *= 1-beat*.035*react_motion
		if _blend.has(key):
			rot = lerpf(_blend[key].rotation,rot,blend); pos = _blend[key].position.lerp(pos,blend); scl = _blend[key].scale.lerp(scl,blend)
		bones[key].rotation = rot; bones[key].position = pos; bones[key].scale = scl
		var edge = (bust or clip == "lock_in") and key in ["head","cape"] and not reduced_motion
		if bones[key].chromatic != edge: bones[key].chromatic = edge; bones[key].queue_redraw()
	if clip in ["mark_push","score_flash"] or reaction.remaining > 0: queue_redraw()
	_mat.set_shader_parameter(&"rim_color",P.mark_color(side))
	_mat.set_shader_parameter(&"power",.9 if power else .1)
	_mat.set_shader_parameter(&"impact",punch if attack and not reduced_motion else 0.0)
	actor.modulate = Color(.72,.78,.9) if stagger else Color.WHITE

func react(event_id: String) -> bool:
	if not reaction.request(event_id,R.index_of(hero_id),reduced_motion): return false
	set_clip(reaction.current); clip_age = 0; _set_expression(Reactions.expression_for(R.index_of(hero_id),reaction.current).id)
	return true
func _set_expression(id: String):
	if expression == id or not bones.has("mouth"): return
	expression = id
	var key = hero_id+"/"+id
	if not FACE_CACHE.has(key): FACE_CACHE[key] = _make_face(id)
	for part in FACE_CACHE[key]:
		bones[part].mesh = FACE_CACHE[key][part]; bones[part].queue_redraw()
func _make_face(id: String) -> Dictionary:
	var parts = {}
	for part in ["eyes","pupils","brows","mouth","symbols"]: parts[part] = Cutout.new()
	var eye: Cutout = parts.eyes; var pupil: Cutout = parts.pupils; var brow: Cutout = parts.brows
	var mouth: Cutout = parts.mouth; var symbol: Cutout = parts.symbols
	var index = R.index_of(hero_id); var h = R.DATA[index]; var iris = Color(h.palette[0]).lightened(.2)
	var dialect: Array = Reactions.DIALECTS[index]; var white = Color("f4f5ee")
	for side_value in [-1,1]:
		var x = side_value*14.0*float(dialect[0]); var asym = side_value*float(dialect[2])
		var by = -12+float(dialect[1]); var angle = -1.0
		var look = Vector2(float(dialect[3]),0)
		match id:
			"smug_grin":
				eye.curve([x-10,1,x-5,-1,x+4,0,x+8,2,x+4,6,x-5,6],white,false)
				by += asym; angle = side_value*2; look.x += 2
			"panic","double_take":
				var ry = 10.0 if id == "panic" or side_value > 0 else 6.0
				eye.curve([x-10,0,x-6,-ry,x+4,-ry,x+10,0,x+6,ry,x-5,ry],white,false)
				by -= 7+asym; angle = -side_value*3
			"celebration":
				eye.line([x-9,4,x-5,-1,x,-2,x+6,2],INK,3)
				by -= 3; angle = -side_value*2
			"sulking":
				eye.curve([x-9,1,x-4,0,x+7,3,x+5,7,x-5,7],white,false)
				by += 3; angle = side_value*4; look.y = 3
			_:
				eye.curve([x-10,0,x-5,-4,x+3,-4,x+8,-1,x+5,5,x-5,6],white,false)
				if id == "eye_roll": look = Vector2(-1,-3); by -= 2; angle = side_value*2
		if id != "celebration":
			var radius = 2.0 if id == "panic" else 3.7
			pupil.dot(Vector2(x+2,1)+look,radius,iris,18)
			pupil.dot(Vector2(x+2,1)+look,radius*.55,INK,16)
			pupil.dot(Vector2(x+1,0)+look,maxf(.75,radius*.28),Color.WHITE,12)
		brow.curve([x-11,by-angle,x-3,by-3,x+7,by+angle-2,x+9,by+angle+1,x-3,by],INK,false,false)
	match id:
		"smug_grin","celebration":
			var depth = 9 if id == "celebration" else 5
			mouth.curve([-15,26,-5,29,7,27,17,22+float(dialect[2]),11,31+depth,0,35+depth,-11,32+depth],INK,false,false)
			mouth.curve([-12,27,-3,30,8,28,14,25,8,32,-2,34,-10,31],white,false,false)
			mouth.line([-7,39,2,40,9,36],iris.darkened(.3),1.4)
		"panic":
			mouth.curve([-10,27,-2,22,8,24,13,33,7,42,-3,44,-12,36],INK,false,false)
			mouth.curve([-7,36,1,34,8,37,4,41,-4,41],Color("d98b9c"),false,false)
		"double_take":
			mouth.curve([2,27,7,24,12,29,11,36,5,37,1,33],INK,false,false)
		"eye_roll": mouth.line([-12,32,-2,30,8,31,13,29],INK,2.3)
		"sulking":
			mouth.line([-14,35,-5,30,5,30,14,34],INK,2.4)
			mouth.line([-6,38,2,39,8,37],iris.darkened(.4),1.5)
		_: mouth.line([-13,29,-4,31,5,30,14,26-float(dialect[2])],INK,2.2)
	match id:
		"panic":
			symbol.curve([34,-23,32,-15,28,-8,30,-3,36,-2,40,-7,38,-14],Color("83dff7"),false)
			symbol.line([34,-14,32,-7],white,1.4)
		"double_take":
			symbol.line([37,-25,42,-25,45,-20,40,-15,40,-12],iris,3)
			symbol.dot(Vector2(40,-7),1.8,iris)
			symbol.line([49,-23,49,-13],Color("ffe6a1"),3); symbol.dot(Vector2(49,-7),1.8,Color("ffe6a1"))
		"eye_roll":
			symbol.line([-39,-22,-35,-18,-39,-14],Color("f58a81"),2.5)
			symbol.line([-33,-24,-29,-20,-25,-24],Color("f58a81"),2.5)
		"celebration":
			for center in [Vector2(39,-20),Vector2(-36,7)]:
				symbol.shape([center.x,center.y-7,center.x+2,center.y-2,center.x+7,center.y,center.x+2,center.y+2,center.x,center.y+7,center.x-2,center.y+2,center.x-7,center.y,center.x-2,center.y-2],Color("ffe7a0"),false,false)
		"sulking":
			for j in range(3): symbol.line([-36+j*4,-23,-37+j*4,-13+j*2],Color("82a3d6"),1.5)
	var result = {}
	for part in parts:
		parts[part].bake(); result[part] = parts[part].mesh; parts[part].free()
	return result

func _draw():
	if (clip not in ["mark_push","score_flash"] and not (reaction.remaining > 0 and reaction.event in ["own_claim","comeback"])) or clip_age > .85: return
	var a = sin(PI*clampf(clip_age/.85,0,1))
	var center = Vector2(size.x*.76,size.y*.2)
	P.mark(self,center,minf(size.x,size.y)*.17,side,a,1.4,true)

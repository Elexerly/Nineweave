extends Control
## Illustrated, lazily loaded pose/face player. The 256px head canvas is never cropped.
const R = preload("res://characters/roster.gd")
const Reactions = preload("res://characters/reactions.gd")
const CLIPS = ["idle","idle_power","idle_stagger","hover_react","lock_in","board_pop","victory","defeat","score_flash","mark_push"]
static var textures: Dictionary = {}
var hero_id: String = "cryon"
var bust: bool = true
var art_key: String = ""
var fit_height: bool = false
var side: int = 1
var facing: int = 1
var reduced_motion: bool = false
var frozen: bool = false
var clip: String = "idle"
var clip_age: float = 0
var expression: String = "neutral"
var reaction = Reactions.new()
var bust_view = Vector2(256,256)
var bust_lift: float = 0
var _face_age: float = 0
var _idle_age: float = 0
var _idle_next: float = 7.5
var _delay: float = 0
var _pending_face: String = ""
var texture: Texture2D
static func get_texture(id: String, key: String) -> Texture2D:
	var safe = R.get_hero(id).id
	var path = "res://assets/heroes/%s/%s.webp" % [safe,key]
	if not textures.has(path): textures[path] = load(path)
	return textures[path]
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE; clip_contents = true
	if is_visible_in_tree(): refresh_texture()
func configure(id: String, as_bust: bool = false):
	hero_id = R.get_hero(id).id; bust = as_bust; expression = "neutral"; _face_age = 0; refresh_texture()
func refresh_texture():
	texture = get_texture(hero_id,art_key if not art_key.is_empty() else ("head_"+expression if bust else "splash"))
	queue_redraw()
func set_clip(value: String):
	if clip == value: return
	clip = value; clip_age = 0
	if value in ["victory","defeat","board_pop","mark_push","score_flash","hover_react"]:
		expression = {"victory":"cheer","defeat":"pout"}.get(value,"smug"); _face_age = 0; refresh_texture()
func react(event: String) -> bool:
	if not reaction.request(event,R.index_of(hero_id),reduced_motion): return false
	clip = reaction.current; clip_age = 0; _face_age = 0; _idle_age = 0
	if event in ["own_claim","opponent_claim","comeback","near_loss"]: reaction.cooldown = maxf(2.0,reaction.cooldown)
	var face = {"own_claim":"smug","comeback":"smug","opponent_claim":"pout","near_loss":"panic","win":"cheer","loss":"pout","opponent_good":"doubletake","own_move":"smug","opponent_move":"eyeroll"}.get(event,"neutral")
	_delay = .28 if event in ["opponent_claim","loss","near_loss"] and not reduced_motion else 0.0
	_pending_face = face
	if _delay == 0: expression = face; refresh_texture()
	return true
func advance(delta: float):
	if frozen: return
	clip_age += delta; _face_age += delta; reaction.advance(delta)
	if _delay > 0:
		_delay -= delta
		if _delay <= 0: expression = _pending_face; refresh_texture()
	if reaction.remaining <= 0 and _face_age > 1.6 and expression != "neutral":
		expression = "neutral"; refresh_texture()
	_idle_age += delta
	if not reduced_motion and reaction.remaining <= 0 and _idle_age >= _idle_next:
		_idle_age = 0; _idle_next = 6.0+float((R.index_of(hero_id)*7+int(clip_age))%5)
		expression = "eyeroll" if side == 2 else "smug"; _face_age = 1.22; refresh_texture()
	queue_redraw()
func _process(delta): advance(delta)
func pose(_time: float = 0): queue_redraw()
func _draw():
	if texture == null or size.x <= 0 or size.y <= 0: return
	var stretch = Vector2.ONE
	if not frozen and not reduced_motion and reaction.remaining > 0 and _delay <= 0:
		var t = maxf(0,_face_age-(.28 if reaction.event in ["opponent_claim","loss","near_loss"] else 0))
		if t < .08: stretch = Vector2(.90,1.08).lerp(Vector2(1.06,.94),t/.08)
		elif t < .20: stretch = Vector2(1.06,.94).lerp(Vector2.ONE,(t-.08)/.12)
	# Leave 4% gutter: even the overshoot is clipped to the original safe region.
	var rect = texture_rect(stretch)
	# Mirror around the control's centre (negative rect sizes are renderer-dependent).
	draw_set_transform_matrix(mirror_transform())
	draw_texture_rect(texture,rect,false)
	draw_set_transform_matrix(Transform2D.IDENTITY)

## Positive draw rectangles plus an explicit centre reflection work on GL/Web alike.
## The render path and the regression test use these very same transforms.
func texture_rect(stretch: Vector2 = Vector2.ONE) -> Rect2:
	if texture == null: return Rect2()
	var factor = size.y/texture.get_height() if fit_height else minf(size.x/texture.get_width(),size.y/texture.get_height())
	var dim = texture.get_size()*factor*(.92 if bust else 1.0)*stretch
	return Rect2((size-dim)*.5,dim)
func mirror_transform() -> Transform2D:
	return Transform2D(0,Vector2(-1,1),0,Vector2(size.x,0)) if facing < 0 else Transform2D.IDENTITY
func visible_art_rect() -> Rect2:
	return (mirror_transform()*texture_rect()).intersection(Rect2(Vector2.ZERO,size))

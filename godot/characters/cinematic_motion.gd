extends RefCounted
## One analytic clock for live play, arbitrary-time screenshots and frame sequences.
## No random(), accumulated physics, asynchronous tweens or wall-clock shader TIME.
const VERSUS_SECONDS = 3.0
const RESULT_SECONDS = 5.0
const CLASH = .35
const BUTTONS_AT = 3.0
const LETTER_STEP = .045
const EXIT_AT = 2.65
const EXIT_TYPE_SECONDS = .12
const WINNER_PARTICLES = 140
static func exit_type_alpha(t: float) -> float:
	return 1.0-clampf((t-EXIT_AT)/EXIT_TYPE_SECONDS,0,1)
static func out_cubic(t: float) -> float: return 1.0-pow(1.0-clampf(t,0,1),3)
static func back(t: float, strength: float = .85) -> float:
	var u = clampf(t,0,1)-1.0
	return 1.0+(strength+1.0)*u*u*u+strength*u*u
static func shake(t: float, reduced: bool) -> Vector2:
	if reduced or t < CLASH or t >= CLASH+.25: return Vector2.ZERO
	var u = t-CLASH
	return Vector2(cos(u*157),sin(u*193)) * 10.0*pow(1.0-u/.25,2)
static func vs_scale(t: float, reduced: bool) -> Vector2:
	if reduced: return Vector2.ONE
	if t >= EXIT_AT: return Vector2.ONE*exit_type_alpha(t)
	if t < CLASH: return Vector2.ZERO
	if t < .44: return Vector2(2.2,1.95).lerp(Vector2(.9,1.08),out_cubic((t-CLASH)/.09))
	return Vector2(.9,1.08).lerp(Vector2.ONE,out_cubic((t-.44)/.12))
static func travel(s: Vector2, rival: bool) -> Vector2:
	var v = Vector2(-s.x*1.6,s.y*.95) if s.x < s.y else Vector2(-s.x*1.15,0)
	return -v if rival else v
static func actor_offset(s: Vector2, t: float, rival: bool, reduced: bool) -> Vector2:
	if reduced: return Vector2.ZERO
	var exit_t = clampf((t-2.65)/.35,0,1)
	# Keep heading through the card on exit, continuing the incoming dash.
	var offset = travel(s,rival)*(1.0-back(t/.35)-exit_t*exit_t)
	if t >= .4 and t < 2.65:
		offset.y += sin((t-.4)*2.6+(PI if rival else 0))*3.5
	return offset
static func breath(t: float, rival: bool, reduced: bool) -> Vector2:
	if reduced or t < .4: return Vector2.ONE
	return Vector2(1,1.0+.0075*(1.0+sin((t-.4)*2.6+(PI if rival else 0))))
static func wipe_offset(s: Vector2, t: float, warm: bool, reduced: bool) -> Vector2:
	if reduced: return Vector2.ZERO
	var v = Vector2(s.x*.65,-s.y*1.15) if s.x < s.y else Vector2(s.x*1.15,-s.y*.35)
	return v*(1 if warm else -1)*(1.0-out_cubic(t/.28)+pow(clampf((t-2.65)/.35,0,1),2))
static func flash(t: float, reduced: bool) -> float:
	# Three frames at 60Hz: hard white / ink / white. Never a long bloom.
	if reduced or t < CLASH or t >= CLASH+.05: return 0
	return 1 if t < CLASH+1.0/60.0 or t >= CLASH+2.0/60.0 else -1
static func letter_start(name_length: int, wins: bool, reduced: bool) -> float:
	if reduced: return .12
	return .50+name_length*LETTER_STEP+.14 if wins else .50
static func letter_scale(t: float, index: int, start: float, reduced: bool) -> float:
	if reduced: return 1
	var u = t-start-index*LETTER_STEP
	if u < 0: return 0
	if u < .13: return lerpf(2.0,.91,out_cubic(u/.13))
	return lerpf(.91,1.0,back((u-.13)/.14,.65))
static func unit(i: int, salt: int = 0) -> float:
	# Fixed integer hash: same seed on native and Web, independent of RNG state.
	var n = posmod((i+1)*104729+(salt+7)*7919,65521)
	n = posmod(n*31337+97,65521)
	return float(n)/65521.0
static func particle(i: int, t: float, s: Vector2, versus: bool, player: int = 1) -> Dictionary:
	# Winner's 108-particle landing plus a 32-particle WINS punctuation burst.
	# The caller supplies local time for the second burst; every pose is seekable.
	var start = CLASH+unit(i,1)*.045 if versus else CLASH+unit(i,1)*.045
	var life = .55+unit(i,2)*.6 if versus else 1.5+unit(i,2)*.5
	var a = t-start
	if a < 0 or a > life: return {}
	var gold = i%2 == 1
	var origin = s*.5 if versus else s*Vector2(.50,.47)
	var angle = unit(i,3)*TAU
	if versus:
		var from_rival = gold if player == 1 else not gold
		var side = travel(s,from_rival).normalized()
		origin += side*minf(s.x,s.y)*.08
		angle = side.angle()+(unit(i,3)-.5)*PI*1.6
	var speed = minf(s.x,s.y)*(.28+unit(i,4)*.7)
	var velocity = Vector2.from_angle(angle)*speed
	if not versus: velocity.y = -absf(velocity.y)-s.y*.16
	var gravity = s.y*(.32 if versus else .85)
	var pos = origin+velocity*a+Vector2(0,gravity*.5*a*a)
	var length = (2+unit(i,6)*4)*clampf(minf(s.x,s.y)/390,1,2) if versus else (6+unit(i,6)*8)*minf(s.x,s.y)/390.0
	var alpha = pow(1-a/life,.7) if versus else 1.0-smoothstep(.65,1.0,a/life)
	return {"position":pos,"angle":angle+a*(unit(i,5)-.5)*12,"length":length,"alpha":alpha,"gold":gold,"confetti":not versus and i%3 != 0}

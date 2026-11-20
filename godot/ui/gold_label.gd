extends Label
## Same letter-space bevel and travelling glint as the Lexerly title.
const GOLD = preload("res://assets/shaders/gold.gdshader")
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clip_text = true
	add_theme_color_override("font_outline_color",Color("1a0f05"))
	add_theme_color_override("font_shadow_color",Color(0,0,0,.8))
	add_theme_constant_override("shadow_offset_y",2)
	material = ShaderMaterial.new()
	material.shader = GOLD
func place(bounds: Rect2, value: String, font: Font, font_size: int, reduced: bool):
	text = value
	add_theme_font_override("font",font)
	add_theme_font_size_override("font_size",font_size)
	add_theme_constant_override("outline_size",clampi(roundi(font_size*.095),2,6))
	position = bounds.position
	size = bounds.size
	var line_top := (bounds.size.y-font.get_height(font_size))*.5
	material.set_shader_parameter("band_top",line_top+font.get_ascent(font_size)-font_size*.74)
	material.set_shader_parameter("band_height",font_size*.78)
	material.set_shader_parameter("motion",0.0 if reduced else 1.0)

shader_type canvas_item;
// Mask only this result badge; the registered source head canvases stay intact.
void fragment() {
	COLOR.a *= 1.0 - smoothstep(0.465, 0.495, length(UV - vec2(0.5)));
}

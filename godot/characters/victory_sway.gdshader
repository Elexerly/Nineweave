shader_type canvas_item;
uniform float cinematic_time = 0.0;
uniform float sway_pixels = 0.0;
void vertex() {
	// Feet stay planted; shoulders, cape and hair follow a quiet, delayed breath.
	VERTEX.x += sin(cinematic_time * 2.1 + 0.35) * sway_pixels * pow(1.0 - UV.y, 2.0);
}

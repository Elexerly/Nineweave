shader_type canvas_item;
render_mode unshaded;
// Geometry already contains authored three-band cel colour + navy ink. No screen
// texture, HDR or neighbour sampling. Edge doubles are geometry on portraits only.
uniform vec4 rim_color : source_color = vec4(0.26,0.86,1.0,1.0);
uniform float power = 0.0;
uniform float impact = 0.0;
void fragment() {
 vec4 c = COLOR;
 float bright = max(c.r,max(c.g,c.b));
 float lit = smoothstep(0.45,0.9,bright);
 c.rgb = mix(c.rgb,c.rgb+rim_color.rgb*0.13*lit,power);
 c.rgb = mix(c.rgb,vec3(1.0,0.96,0.82),impact*0.42*lit);
 COLOR = c;
}

shader_type canvas_item;
render_mode unshaded;
void fragment() {
 vec4 tex = texture(TEXTURE,UV);
 float bevel = 0.55 + 0.45 * cos(UV.y*9.0);
 float gleam = pow(max(0.0,sin(UV.x*9.0-TIME*0.48+UV.y*3.0)),18.0)*0.17;
 vec3 gold = mix(vec3(0.46,0.25,0.06),vec3(1.0,0.89,0.58),bevel)+gleam;
 COLOR=vec4(gold,tex.a)*COLOR;
}

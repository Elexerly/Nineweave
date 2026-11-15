shader_type canvas_item;
render_mode unshaded;
// Bevelled gold lettering: vertical metal gradient in label space (not atlas UV),
// a bright mid-band, a dark bronze base and a travelling glint. Outline/shadow
// passes keep their own dark colour because the result is multiplied by COLOR.
uniform float band_top = 0.0;
uniform float band_height = 60.0;
uniform float motion = 1.0;
varying vec2 local;
void vertex() { local = VERTEX; }
void fragment() {
 vec4 tex = texture(TEXTURE,UV);
 float t = clamp((local.y-band_top)/band_height,0.0,1.0);
 vec3 top = vec3(1.0,0.96,0.78);
 vec3 upper = vec3(0.98,0.80,0.40);
 vec3 mid = vec3(0.80,0.54,0.18);
 vec3 lower = vec3(1.0,0.86,0.5);
 vec3 base = vec3(0.45,0.25,0.06);
 vec3 gold = t < 0.35 ? mix(top,upper,t/0.35) : (t < 0.55 ? mix(upper,mid,(t-0.35)/0.2) : (t < 0.72 ? mix(mid,lower,(t-0.55)/0.17) : mix(lower,base,(t-0.72)/0.28)));
 float glint = pow(max(0.0,sin(local.x*0.025-TIME*0.9*motion+local.y*0.01)),40.0)*0.55;
 COLOR = vec4(gold+glint,tex.a)*COLOR;
}

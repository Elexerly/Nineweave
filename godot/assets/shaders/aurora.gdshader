shader_type canvas_item;
render_mode unshaded;
uniform float strength = 0.35;
void fragment() {
 vec2 p = UV - vec2(0.5,0.58);
 float a = atan(p.y,p.x);
 float r = length(p);
 float rays = pow(max(0.0,sin(a*13.0+TIME*0.035)),14.0);
 float glow = exp(-r*5.0);
 float shimmer = sin(UV.y*11.0+TIME*0.06+sin(UV.x*7.0))*0.5+0.5;
 COLOR = vec4(mix(vec3(0.07,0.35,0.65),vec3(0.75,0.5,0.16),rays*0.55),glow*(0.12+rays*0.08+shimmer*0.025)*strength);
}

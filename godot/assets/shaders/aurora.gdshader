shader_type canvas_item;
render_mode unshaded;
// Round 2 sky: soft drifting cloud banks (3-octave value noise), fanning warm light rays
// from behind the title and a cool horizon glow. One full-screen quad; cheap on phones.
uniform vec2 ray_center = vec2(0.5,0.2);
uniform float ray_strength = 0.6;
uniform vec3 ray_color = vec3(1.0,0.78,0.38);
uniform float cloud_strength = 0.5;
uniform float aspect = 0.46;
uniform float motion = 1.0;
float hash(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p){
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
float fbm(vec2 p){ float v=0.0; float a=0.5; for(int i=0;i<3;i++){ v+=a*noise(p); p*=2.03; a*=0.5; } return v; }
void fragment() {
 float t = TIME*motion;
 vec2 uv = UV;
 vec2 q = vec2(uv.x*aspect,uv.y);
 // Cloud banks thicken towards the lower half, drifting slowly sideways.
 float band = smoothstep(0.25,0.75,uv.y)*0.8+0.2;
 float c = fbm(q*vec2(3.0,6.5)+vec2(t*0.012,0.0));
 c = smoothstep(0.45,0.85,c)*band;
 vec3 cloud = mix(vec3(0.10,0.22,0.42),vec3(0.42,0.55,0.78),c);
 // Light rays from behind the title.
 vec2 d = (uv-ray_center)*vec2(aspect,1.0);
 float r = length(d);
 float a = atan(d.y,d.x);
 float rays = pow(max(0.0,sin(a*11.0+t*0.05)),10.0)*0.7+pow(max(0.0,sin(a*7.0-t*0.03+1.3)),16.0)*0.5;
 float fall = exp(-r*2.4);
 vec3 light = ray_color*(rays*fall*0.55+exp(-r*6.0)*0.35)*ray_strength;
 // Cool horizon glow behind the castle line.
 vec3 horizon = vec3(0.15,0.45,0.9)*exp(-abs(uv.y-0.55)*7.0)*0.18;
 vec3 col = cloud*c*cloud_strength+light+horizon;
 float alpha = clamp(max(max(col.r,col.g),col.b),0.0,1.0);
 COLOR = vec4(col/max(alpha,0.001),alpha);
}

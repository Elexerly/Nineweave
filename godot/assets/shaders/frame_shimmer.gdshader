shader_type canvas_item;
render_mode unshaded;
uniform float motion = 1.0;
void fragment() {
 float mask = 0.0;
 for (int b=0;b<9;b++) {
   vec2 origin = vec2(0.022)+vec2(float(b%3),float(b/3))*0.32466667;
   vec2 q = UV-origin;
   if(q.x>0.0 && q.y>0.0 && q.x<0.30666667 && q.y<0.30666667) {
     float edge = min(min(q.x,q.y),min(0.30666667-q.x,0.30666667-q.y));
     mask = max(mask,1.0-smoothstep(0.001,0.004,edge));
   }
 }
 float edge = min(min(UV.x,UV.y),min(1.0-UV.x,1.0-UV.y));
 mask = max(mask,1.0-smoothstep(0.003,0.008,edge));
 float gleam = pow(max(0.0,sin((UV.x+UV.y)*7.0-TIME*0.35*motion)),22.0);
 COLOR = vec4(1.0,0.88,0.52,mask*gleam*0.38);
}

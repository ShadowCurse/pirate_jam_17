#version 300 es
precision highp float;

in vec2 vert_position;

out vec4 frag_color;

uniform float transparancy;
uniform float radius;
uniform float width;

void main() {
  float outer = radius;
  float inner = radius * 0.85;
  vec2 center_left = vec2(-width, 0.0);
  vec2 center_right = vec2(width, 0.0);
  if (vert_position.x < center_left.x) {
      float v2 = length(vert_position - center_left);
      if (v2 < radius) {
          v2 = smoothstep(outer, inner, v2); 
          frag_color = vec4(v2);
      } else
          frag_color = vec4(0.0);
  } else if (center_right.x < vert_position.x) {
      float v2 = length(vert_position - center_right);
      if (v2 < radius) {
          v2 = smoothstep(outer, inner, v2); 
          frag_color = vec4(v2);
      } else
          frag_color = vec4(0.0);
  } else {
    float v2 = abs(vert_position.y);
    if (v2 < radius) {
        v2 = smoothstep(outer, inner, v2); 
        frag_color = vec4(v2);
    } else
        frag_color = vec4(0.0);
  }

  frag_color.a *= transparancy;
}

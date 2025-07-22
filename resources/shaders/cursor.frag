#version 300 es
precision highp float;

in vec2 vert_position;

out vec4 frag_color;

uniform float size;

#define MAX_SIZE 0.05

void main() {
  float outer = 0.018;
  float inner = 0.016;
  float v = smoothstep(outer, inner, dot(vert_position, vert_position));
  frag_color = vec4(v, v, v, v * size / MAX_SIZE);
}

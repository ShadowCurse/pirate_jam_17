#version 300 es
precision highp float;

out vec4 frag_color;

uniform float size;
uniform vec2 window_size;

#define MAX_SIZE 0.05

void main() {
  vec2 scale = vec2(size, window_size.x / window_size.y * size);
  vec2 coord = (gl_FragCoord.xy / window_size - 0.5) / scale;

  float outer = 0.006;
  float inner = 0.004;
  float v = smoothstep(outer, inner, dot(coord, coord));
  frag_color = vec4(v, v, v, v * size / MAX_SIZE);
}

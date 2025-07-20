#version 300 es
precision highp float;

out vec4 frag_color;

uniform vec2 size;

void main() {
  vec2 coord = (gl_FragCoord.xy / vec2(1280, 720) - 0.5) / size;

  float outer = 0.006;
  float inner = 0.004;
  float v = smoothstep(outer, inner, dot(coord, coord));
  frag_color = vec4(v, v, v, v * 0.8);
}

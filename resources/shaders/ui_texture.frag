#version 300 es
precision highp float;

in vec2 vert_position;

out vec4 frag_color;

uniform float transparancy;
uniform sampler2D ui_texture;

void main() {
  vec2 uv = (vert_position + 1.0) / 2.0;
  frag_color = texture(ui_texture, uv);
  frag_color.a *= transparancy;
}

#version 300 es
precision highp float;

in vec2 vert_position;

out vec4 frag_color;

uniform sampler2D ui_texture;

void main() {
  frag_color = texture(ui_texture, vert_position);
}

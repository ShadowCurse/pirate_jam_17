#version 300 es
precision highp float;

in vec2 vert_position;

out vec4 frag_color;

uniform vec2 window_size;
uniform float blur_strength;
uniform sampler2D framebuffer_texture;

// https://github.com/Experience-Monks/glsl-fast-gaussian-blur/blob/master/13.glsl
vec4 blur13(sampler2D image, vec2 uv, vec2 resolution, vec2 direction) {
  vec4 color = vec4(0.0);
  vec2 off1 = vec2(1.411764705882353) * direction;
  vec2 off2 = vec2(3.2941176470588234) * direction;
  vec2 off3 = vec2(5.176470588235294) * direction;
  color += texture2D(image, uv) * 0.1964825501511404;
  color += texture2D(image, uv + (off1 / resolution)) * 0.2969069646728344;
  color += texture2D(image, uv - (off1 / resolution)) * 0.2969069646728344;
  color += texture2D(image, uv + (off2 / resolution)) * 0.09447039785044732;
  color += texture2D(image, uv - (off2 / resolution)) * 0.09447039785044732;
  color += texture2D(image, uv + (off3 / resolution)) * 0.010381362401148057;
  color += texture2D(image, uv - (off3 / resolution)) * 0.010381362401148057;
  return color;
}

void main() {
  vec2 uv = (vert_position + 1.0) / 2.0;

  if (blur_strength < 0.01)
    frag_color = texture(framebuffer_texture, uv);
  else
    frag_color = (blur13(framebuffer_texture, uv, window_size, vec2(blur_strength * 2.0, 0.0)) +
                 blur13(framebuffer_texture, uv, window_size, vec2(0.0, blur_strength * 2.0))) / 2.0;
    frag_color *= (1.0 - blur_strength) / 2.0 + 0.5;
}

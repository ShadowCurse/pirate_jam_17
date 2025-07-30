#version 300 es
precision highp float;

flat in vec4 vert_roughness_emissive_uv_scale_options;

#define NO_DIRECT_LIGHT_SHADOW           (1 << 4)

void main() {
    int options = floatBitsToInt(vert_roughness_emissive_uv_scale_options.a);
    if ((options & NO_DIRECT_LIGHT_SHADOW) != 0)
      discard;
}

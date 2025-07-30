#version 300 es
precision highp float;

in vec3 vert_position;
flat in vec4 vert_roughness_emissive_uv_scale_options;

uniform vec3 light_position;
uniform float far_plane;

#define NO_POINT_LIGHT_SHADOW            (1 << 5)

void main() {
    int options = floatBitsToInt(vert_roughness_emissive_uv_scale_options.a);
    if ((options & NO_POINT_LIGHT_SHADOW) != 0)
      discard;

    float light_distance = length(vert_position - light_position);
    light_distance = light_distance / far_plane;
    gl_FragDepth = light_distance;
}

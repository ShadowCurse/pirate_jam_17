#version 300 es
precision highp float;

in vec3 in_position;
in float in_uv_x;
in vec3 in_normal;
in float in_uv_y;
in vec4 in_tangent;
in vec4 in_color;

out vec3 vert_position;
out vec3 vert_normal;
out vec2 vert_uv;
out vec4 vert_color;
out vec4 vert_light_space_position;
out mat3 tbn_matrix;

uniform mat4 view;
uniform mat4 projection;
uniform mat4 model;
uniform mat4 shadow_map_view;
uniform mat4 shadow_map_projection;
uniform float uv_scale;

void main() {
    vec4 world_position = model * vec4(in_position, 1.0);
    gl_Position = projection * view * world_position;
    vert_position = world_position.xyz;
    vert_normal = mat3(model) * in_normal;
    // need to use all attributes, otherwise webgl will
    // play idiot and remove them and everything will be incorrect.
    vert_uv = vec2(in_uv_x, in_uv_y) * uv_scale;
    vert_color = in_color;
    vert_light_space_position = shadow_map_projection * shadow_map_view * world_position;

    vec3 bitangent = cross(in_normal, in_tangent.xyz) * in_tangent.w;
    vec3 T = normalize(vec3(model * vec4(in_tangent.xyz, 0.0)));
    vec3 B = normalize(vec3(model * vec4(bitangent,  0.0)));
    vec3 N = normalize(vec3(model * vec4(in_normal,  0.0)));
    tbn_matrix = mat3(T, B, N);
}

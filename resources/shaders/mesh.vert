#version 300 es
precision highp float;

layout (location = 0) in vec3 in_position;
layout (location = 1) in float in_uv_x;
layout (location = 2) in vec3 in_normal;
layout (location = 3) in float in_uv_y;
layout (location = 4) in vec4 in_tangent;
layout (location = 5) in vec4 in_color;

// Instance data
layout (location = 6)  in mat4 in_model;
layout (location = 10) in vec4 in_albedo_metallic;
layout (location = 11) in vec4 in_roughness_emissive_uv_scale_options;

out vec3 vert_position;
out vec3 vert_normal;
out vec2 vert_uv;
out vec4 vert_color;
out vec4 vert_light_space_position;
out mat3 tbn_matrix;
flat out vec4 vert_albedo_metallic;
flat out vec4 vert_roughness_emissive_uv_scale_options;

uniform mat4 view;
uniform mat4 projection;
uniform mat4 shadow_map_view;
uniform mat4 shadow_map_projection;

void main() {
    vec4 world_position = in_model * vec4(in_position, 1.0);
    gl_Position = projection * view * world_position;

    vert_position = world_position.xyz;
    vert_normal = mat3(in_model) * in_normal;
    // need to use all attributes, otherwise webgl will
    // play idiot and remove them and everything will be incorrect.
    float uv_scale = in_roughness_emissive_uv_scale_options.z;
    vert_uv = vec2(in_uv_x, in_uv_y) * uv_scale;
    vert_color = in_color;
    vert_light_space_position = shadow_map_projection * shadow_map_view * world_position;
    vert_albedo_metallic = in_albedo_metallic;
    vert_roughness_emissive_uv_scale_options = in_roughness_emissive_uv_scale_options;

    vec3 bitangent = cross(in_normal, in_tangent.xyz) * in_tangent.w;
    vec3 T = normalize(vec3(in_model * vec4(in_tangent.xyz, 0.0)));
    vec3 B = normalize(vec3(in_model * vec4(bitangent,  0.0)));
    vec3 N = normalize(vec3(in_model * vec4(in_normal,  0.0)));
    tbn_matrix = mat3(T, B, N);
}

#version 300 es
precision mediump float;

in vec3 in_position;
in float in_uv_x;
in vec3 in_normal;
in float in_uv_y;
in vec4 in_color;

out vec3 vert_position;
out vec3 vert_normal;

uniform mat4 view;
uniform mat4 projection;
uniform mat4 model;

void main() {
    vec4 world_position = model * vec4(in_position, 1.0);
    gl_Position = projection * view * world_position;
    vert_position = world_position.xyz;
    vert_normal = in_normal;
}

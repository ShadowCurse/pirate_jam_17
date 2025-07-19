#version 300 es
precision mediump float;

in vec3 in_position;
in float in_uv_x;
in vec3 in_normal;
in float in_uv_y;
in vec4 in_color;

out vec3 vert_normal;
out vec2 vert_uv;
out vec4 vert_color;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

void main() {
    vec4 world_position = model * vec4(in_position, 1.0);
    gl_Position = projection * view * world_position;
    vert_normal = in_normal;
    // need to use all attributes, otherwise webgl will
    // play idiot and remove them and everything will be incorrect.
    vert_uv = vec2(in_uv_x, in_uv_y);
    vert_color = in_color;
}

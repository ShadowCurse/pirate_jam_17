#version 300 es
precision highp float;

out vec2 vert_position;

vec2 grid_planes[6] = vec2[](
    vec2(1, 1), vec2(-1, 1), vec2(-1, -1),
    vec2(-1, -1), vec2(1, -1), vec2(1, 1)
);

void main() {
    vert_position = grid_planes[gl_VertexID];
    gl_Position = vec4(grid_planes[gl_VertexID], 0.0, 1.0);
}

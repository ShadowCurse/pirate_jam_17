#version 300 es
precision highp float;

uniform vec2 size;

vec2 grid_planes[6] = vec2[](
    vec2(1, 1), vec2(-1, 1), vec2(-1, -1),
    vec2(-1, -1), vec2(1, -1), vec2(1, 1)
);

void main() {
    vec2 point = grid_planes[gl_VertexID];
    point *= size;
    gl_Position = vec4(point, 0.0, 1.0);
}

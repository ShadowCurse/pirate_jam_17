#version 300 es
precision highp float;

uniform float size;
uniform vec2 window_size;

vec2 grid_planes[6] = vec2[](
    vec2(1, 1), vec2(-1, 1), vec2(-1, -1),
    vec2(-1, -1), vec2(1, -1), vec2(1, 1)
);

void main() {
    vec2 point = grid_planes[gl_VertexID];
    vec2 scale = vec2(size, window_size.x / window_size.y * size);
    point *= scale;
    gl_Position = vec4(point, 0.0, 1.0);
}

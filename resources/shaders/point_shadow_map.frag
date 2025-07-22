#version 300 es
precision highp float;

in vec3 vert_position;

uniform vec3 light_position;
uniform float far_plane;

void main() {
    float light_distance = length(vert_position - light_position);
    light_distance = light_distance / far_plane;
    gl_FragDepth = light_distance;
}

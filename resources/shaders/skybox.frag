#version 300 es
precision highp float;

out vec4 frag_color;

in vec3 vert_position;

uniform samplerCube skybox;

void main() {
    frag_color = texture(skybox, vert_position);
}


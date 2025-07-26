#version 300 es
precision highp float;

out vec3 vert_position;

uniform mat4 view;
uniform mat4 projection;

vec3 vertices[36] = vec3[](
  // +X face
  vec3( 1.0, -1.0,  1.0),
  vec3( 1.0,  1.0,  1.0),
  vec3( 1.0,  1.0, -1.0),

  vec3( 1.0,  1.0, -1.0),
  vec3( 1.0, -1.0, -1.0),
  vec3( 1.0, -1.0,  1.0),

  // +Y face
  vec3( 1.0,  1.0,  1.0),
  vec3(-1.0,  1.0,  1.0),
  vec3(-1.0,  1.0, -1.0),

  vec3(-1.0,  1.0, -1.0),
  vec3( 1.0,  1.0, -1.0),
  vec3( 1.0,  1.0,  1.0),

  // +Z face
  vec3(1.0,   1.0,  1.0),
  vec3(1.0, -1.0,  1.0),
  vec3(-1.0, -1.0,  1.0),

  vec3(-1.0, -1.0,  1.0),
  vec3(-1.0,  1.0,  1.0),
  vec3(1.0,   1.0,  1.0),

  // -X face
  vec3(-1.0, -1.0,  1.0),
  vec3(-1.0, -1.0, -1.0),
  vec3(-1.0,  1.0, -1.0),

  vec3(-1.0,  1.0, -1.0),
  vec3(-1.0,  1.0,  1.0),
  vec3(-1.0, -1.0,  1.0),

  // -Y face
  vec3( 1.0, -1.0,  1.0),
  vec3( 1.0, -1.0, -1.0),
  vec3(-1.0, -1.0, -1.0),

  vec3(-1.0, -1.0, -1.0),
  vec3(-1.0, -1.0,  1.0),
  vec3( 1.0, -1.0,  1.0),

  // +Z face
  vec3( 1.0,  1.0, -1.0),
  vec3(-1.0,  1.0, -1.0),
  vec3(-1.0, -1.0, -1.0),

  vec3(-1.0, -1.0, -1.0),
  vec3( 1.0, -1.0, -1.0),
  vec3( 1.0,  1.0, -1.0)
);

void main() {
    vert_position = vertices[gl_VertexID];
    vec4 v = projection * vec4(mat3(view) * vert_position, 1.0);
    // because of the inverse depth, 0 is the far value
    v.z = 0.0;
    gl_Position = v;
}

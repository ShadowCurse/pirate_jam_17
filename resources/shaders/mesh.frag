#version 300 es
precision highp float;

#define WEBGL 0

in vec3 vert_position;
in vec3 vert_normal;
in vec2 vert_uv;
in vec4 vert_color;
in vec4 vert_light_space_position;

out vec4 frag_color;

#define NUM_LIGHTS 4
uniform vec3 camera_position;
uniform vec3 light_positions[NUM_LIGHTS];
uniform vec3 light_colors[NUM_LIGHTS];
uniform vec3 direct_light_direction;
uniform vec3 direct_light_color;
uniform vec3 albedo;
uniform float metallic;
uniform float roughness;
uniform float ao;
uniform float emissive_strength;

uniform int use_shadow_map;
uniform sampler2D direct_light_shadow;
uniform samplerCube point_light_0_shadow;
uniform samplerCube point_light_1_shadow;
uniform samplerCube point_light_2_shadow;
uniform samplerCube point_light_3_shadow;

const float PI = 3.14159265359;

vec3 fresnel_schlick(float cos_theta, vec3 f0) {
    return f0 + (1.0 - f0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}  

float distribution_ggx(vec3 normal, vec3 half_vector, float roughness) {
    float a        = roughness *  roughness;
    float a2       = a * a;
    float n_dot_h  = max(dot(normal, half_vector), 0.0);
    float n_dot_h2 = n_dot_h * n_dot_h;
	
    float num   = a2;
    float denom = (n_dot_h2 * (a2 - 1.0) + 1.0);
    denom       = PI * denom * denom;
	
    return num / denom;
}

float geometry_schlick_ggx(float d, float roughness) {
    float r = (roughness + 1.0);
    float k = (r*r) / 8.0;

    float num   = d;
    float denom = d * (1.0 - k) + k;
	
    return num / denom;
}
float geometry_smith(float ndl, float ndc, float roughness) {
    float ggx1 = geometry_schlick_ggx(ndl, roughness);
    float ggx2 = geometry_schlick_ggx(ndc, roughness);
    return ggx1 * ggx2;
}

float direct_shadow(vec4 light_space_position, vec3 normal, vec3 to_light) {
  vec3 projection = light_space_position.xyz / light_space_position.w;
  if (1.0 < projection.z)
    return 0.0;

  vec3 uv = projection * 0.5 + 0.5;
#if WEBGL
  if (uv.x < -1.0 || 1.0 < uv.x ||
      uv.y < -1.0 || 1.0 < uv.y)
    return 0.0;
#endif

  float curr_depth = projection.z;
  float bias = max(0.010 * (1.0 - dot(normal, to_light)), 0.002);

  float shadow = 0.0;
  vec2 texel_size = vec2(1.0) / vec2(textureSize(direct_light_shadow, 0));
  for(int x = -1; x <= 1; ++x) {
      for(int y = -1; y <= 1; ++y) {
          float pcf_depth = texture(direct_light_shadow, uv.xy + vec2(x, y) * texel_size).r;
#if WEBGL
          // for some reason on web the depth is from 0.5 to 1.0
          pcf_depth = (pcf_depth - 0.5) * 2.0;
#endif
          shadow += pcf_depth < curr_depth - bias ? 1.0 : 0.0;
      }
  }
  shadow /= 9.0;
  return shadow;
}

float point_shadow(vec3 normal, vec3 from_light, int light_index) {
    float curr_depth = length(from_light);

    float closest_depth = 0.0;
    switch  (light_index) {
      case 0: closest_depth = texture(point_light_0_shadow, from_light).r; break;
      case 1: closest_depth = texture(point_light_1_shadow, from_light).r; break;
      case 2: closest_depth = texture(point_light_2_shadow, from_light).r; break;
      case 3: closest_depth = texture(point_light_3_shadow, from_light).r; break;
    }
    // Far parameter of the camera
    closest_depth *= 10000.0;

    float bias = max(0.005 * (1.0 - dot(normal, from_light)), 0.001);
    return closest_depth < curr_depth - bias ? 1.0 : 0.0;
}

void main() {
    vec3 normal = normalize(vert_normal);
    vec3 to_camera = normalize(camera_position - vert_position);

    vec3 base_reflectivity = vec3(0.04); 
    base_reflectivity = mix(base_reflectivity, albedo, metallic);

    vec3 radiance_out = vec3(0.0);
    for(int i = 0; i < NUM_LIGHTS; ++i) {
        // calculate per-light radiance
        vec3 to_light     = normalize(light_positions[i] - vert_position);
        vec3 half_vector  = normalize(to_camera + to_light);

        float ndl = max(dot(normal, to_light), 0.0);
        float ndc = max(dot(normal, to_camera), 0.0);
        float ndh = max(dot(half_vector, to_camera), 0.0);

        float distance    = length(light_positions[i] - vert_position);
        float attenuation = 1.0 / (distance * distance);
        vec3 radiance     = light_colors[i] * attenuation;
        
        // cook-torrance brdf
        float normalDF = distribution_ggx(normal, half_vector, roughness);
        float G        = geometry_smith(ndl, ndc, roughness);
        vec3  F        = fresnel_schlick(ndh, base_reflectivity);
        
        vec3 kS = F;
        vec3 kD = vec3(1.0) - kS;
        kD *= 1.0 - metallic;
        
        vec3 numerator    = normalDF * G * F;
        float denominator = 4.0 * ndc * ndl + 0.0001;
        vec3 specular     = numerator / denominator;

        float point_shadow_value = 1.0;
        if (use_shadow_map == 1) {
            vec3 from_light = vert_position - light_positions[i];
            point_shadow_value = (1.0 - point_shadow(normal, from_light, i));
        }

        // add to outgoing radiance
        radiance_out += (kD * albedo / PI + specular) * radiance * ndl * point_shadow_value;
    }

    // Direct light
    {
        // calculate per-light radiance
        vec3 to_light     = normalize(-direct_light_direction);
        vec3 half_vector  = normalize(to_camera + to_light);

        float ndl = max(dot(normal, to_light), 0.0);
        float ndc = max(dot(normal, to_camera), 0.0);
        float ndh = max(dot(half_vector, to_camera), 0.0);

        vec3 radiance = direct_light_color;
        
        // cook-torrance brdf
        float normalDF = distribution_ggx(normal, half_vector, roughness);
        float G        = geometry_smith(ndl, ndc, roughness);
        vec3  F        = fresnel_schlick(ndh, base_reflectivity);
        
        vec3 kS = F;
        vec3 kD = vec3(1.0) - kS;
        kD *= 1.0 - metallic;	  
        
        vec3 numerator    = normalDF * G * F;
        float denominator = 4.0 * ndc * ndl + 0.0001;
        vec3 specular     = numerator / denominator;  
            
        float shadow_value = 1.0;
        if (use_shadow_map == 1)
          shadow_value = (1.0 - direct_shadow(vert_light_space_position, normal, to_light));
        // add to outgoing radiance
        radiance_out += (kD * albedo / PI + specular) * radiance * ndl * shadow_value;
    }

    vec3 ambient = albedo * ao;
    vec3 color = ambient + radiance_out + albedo * emissive_strength;

    color = color / (color + vec3(1.0));
    color = pow(color, vec3(1.0 / 2.2));  
   
    frag_color = vec4(color, 1.0);
}

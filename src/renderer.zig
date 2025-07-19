const std = @import("std");
const gl = @import("bindings/gl.zig");
const log = @import("log.zig");
const math = @import("math.zig");
const gpu = @import("gpu.zig");
const shaders = @import("shaders.zig");

const Camera = @import("root").Camera;
const Mesh = @import("mesh.zig");

var mesh_shader: shaders.MeshShader = undefined;
var mesh_infos: std.BoundedArray(RenderMeshInfo, 128) = .{};

var shadow_map_shader: shaders.ShadowMapShader = undefined;
var shadow_map: gpu.ShadowMap = undefined;

const RenderMeshInfo = struct {
    mesh: *const gpu.Mesh,
    model: math.Mat4,
    material: Mesh.Material,
};

pub const NUM_LIGHTS = 4;
pub const Environment = struct {
    lights_position: [NUM_LIGHTS]math.Vec3 = .{math.Vec3{}} ** NUM_LIGHTS,
    lights_color: [NUM_LIGHTS]math.Color3 = .{math.Color3{}} ** NUM_LIGHTS,
    direct_light_direction: math.Vec3 = .{},
    direct_light_color: math.Color3 = .{},
    use_shadow_map: bool = true,
    shadow_map_width: f32 = 10.0,
    shadow_map_height: f32 = 10.0,
    shadow_map_depth: f32 = 50.0,

    pub fn shadow_map_view(e: *const Environment) math.Mat4 {
        return math.Mat4.look_at(
            .{},
            e.direct_light_direction,
            math.Vec3.Z,
        )
            .mul(Camera.ORIENTATION.to_mat4())
            .translate(e.direct_light_direction.normalize().mul_f32(-10.0))
            .inverse();
    }

    pub fn shadow_map_projection(e: *const Environment) math.Mat4 {
        var projection = math.Mat4.orthogonal(
            e.shadow_map_width,
            e.shadow_map_height,
            e.shadow_map_depth,
        );
        projection.j.y *= -1.0;
        return projection;
    }
};

const Self = @This();

pub fn init() void {
    Self.mesh_shader = .init();
    Self.shadow_map_shader = .init();
    Self.shadow_map = .init();
}

pub fn reset() void {
    Self.mesh_infos.clear();
}

pub fn clear_current_buffers() void {
    gl.glClearDepth(0.0);
    gl.glClearColor(0.0, 0.0, 0.0, 1.0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);
}

pub fn draw_mesh(
    mesh: *const gpu.Mesh,
    model: math.Mat4,
    material: Mesh.Material,
) void {
    const mesh_info = RenderMeshInfo{
        .mesh = mesh,
        .model = model,
        .material = material,
    };
    Self.mesh_infos.append(mesh_info) catch {
        log.warn(@src(), "Cannot add more meshes to draw queue", .{});
    };
}

fn prepare_shadow_map_context() void {
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, Self.shadow_map.framebuffer);
    gl.glClearDepth(1.0);
    gl.glClear(gl.GL_DEPTH_BUFFER_BIT);
    gl.glDepthFunc(gl.GL_LEQUAL);
}

fn prepare_mesh_context() void {
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0);
    gl.glClearDepth(0.0);
    gl.glClearColor(0.0, 0.0, 0.0, 1.0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);
    gl.glDepthFunc(gl.GL_GEQUAL);
}

pub fn render(
    camera: *const Camera,
    environment: *const Environment,
) void {
    prepare_shadow_map_context();
    Self.shadow_map_shader.use();
    Self.shadow_map_shader.set_params(environment);
    for (Self.mesh_infos.slice()) |*mi| {
        Self.shadow_map_shader.set_mesh_params(&mi.model);
        mi.mesh.draw();
    }

    prepare_mesh_context();
    Self.mesh_shader.use();
    const view = camera.transform().inverse();
    const projection = camera.perspective();
    Self.mesh_shader.set_scene_params(
        &view,
        &camera.position,
        &projection,
        environment,
        &Self.shadow_map,
    );
    for (Self.mesh_infos.slice()) |*mi| {
        Self.mesh_shader.set_mesh_params(&mi.model, &mi.material);
        mi.mesh.draw();
    }
}

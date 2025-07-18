const std = @import("std");
const gl = @import("bindings/gl.zig");
const log = @import("log.zig");
const math = @import("math.zig");
const gpu = @import("gpu.zig");
const shaders = @import("shaders.zig");

const Camera = @import("root").Camera;
const Mesh = @import("mesh.zig");

pub var mesh_shader: shaders.MeshShader = undefined;
pub var mesh_infos: std.BoundedArray(RenderMeshInfo, 128) = .{};

const RenderMeshInfo = struct {
    mesh: *const gpu.Mesh,
    model: math.Mat4,
    material: Mesh.Material,
};

pub const NUM_LIGHTS = 4;
pub const Environment = struct {
    lights_position: [NUM_LIGHTS]math.Vec3,
    lights_color: [NUM_LIGHTS]math.Color3,
    direct_light_direction: math.Vec3,
    direct_light_color: math.Color3,
};

const Self = @This();

pub fn init() void {
    Self.mesh_shader = .init();
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

pub fn render(
    camera: *const Camera,
    environment: *const Environment,
) void {
    Self.clear_current_buffers();

    Self.mesh_shader.use();
    const view = camera.transform().inverse();
    const projection = camera.perspective();
    Self.mesh_shader.set_scene_params(
        &view,
        &camera.position,
        &projection,
        environment,
    );
    for (Self.mesh_infos.slice()) |*mi| {
        Self.mesh_shader.set_mesh_params(&mi.model, &mi.material);
        mi.mesh.draw();
    }
}

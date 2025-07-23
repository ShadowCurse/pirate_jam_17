const std = @import("std");
const gl = @import("bindings/gl.zig");
const log = @import("log.zig");
const math = @import("math.zig");
const gpu = @import("gpu.zig");
const shaders = @import("shaders.zig");

const Platform = @import("platform.zig");

const Camera = @import("root").Camera;
const Mesh = @import("mesh.zig");

var mesh_shader: shaders.MeshShader = undefined;
var mesh_infos: std.BoundedArray(RenderMeshInfo, 128) = .{};

var shadow_map_shader: shaders.ShadowMapShader = undefined;
var shadow_map: gpu.ShadowMap = undefined;

var point_shadow_map_shader: shaders.PointShadowMapShader = undefined;
var point_shadow_maps: gpu.PointShadowMaps = undefined;

var cursor_shader: shaders.CursorShader = undefined;

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
    cursor_size: f32 = 0.05,

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

    pub fn point_shadow_map_views(e: *const Environment, light_index: u32) [6]math.Mat4 {
        var r: [6]math.Mat4 = undefined;
        for (
            &[_]struct { math.Vec3, math.Vec3 }{
                .{ .X, .NEG_Y },
                .{ .NEG_X, .NEG_Y },
                .{ .Y, .Z },
                .{ .NEG_Y, .NEG_Z },
                .{ .Z, .NEG_Y },
                .{ .NEG_Z, .NEG_Y },
            },
            &r,
        ) |d, *rr| {
            const v = math.Mat4.look_at(.{}, d[0], d[1])
                .mul(Camera.ORIENTATION.to_mat4())
                .translate(e.lights_position[light_index])
                .inverse();
            rr.* = v;
        }
        return r;
    }

    pub fn point_shadow_map_projection(e: *const Environment) math.Mat4 {
        _ = e;
        var m = math.Mat4.perspective(
            std.math.pi / 2.0,
            @as(f32, @floatFromInt(Platform.WINDOW_WIDTH)) /
                @as(f32, @floatFromInt(Platform.WINDOW_WIDTH)),
            0.01,
            10000.0,
        );
        // flip Y for opengl
        m.j.y *= -1.0;
        return m;
    }
};

const Self = @This();

pub fn init() void {
    Self.mesh_shader = .init();
    Self.shadow_map_shader = .init();
    Self.shadow_map = .init();
    Self.point_shadow_map_shader = .init();
    Self.point_shadow_maps = .init();
    Self.cursor_shader = .init();
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

fn prepare_point_shadow_map_context() void {
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, Self.point_shadow_maps.framebuffer);
    gl.glViewport(0, 0, gpu.PointShadowMaps.SHADOW_WIDTH, gpu.PointShadowMaps.SHADOW_HEIGHT);
    gl.glDepthFunc(gl.GL_LEQUAL);
}

fn prepare_mesh_context() void {
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0);
    gl.glViewport(0, 0, Platform.WINDOW_WIDTH, Platform.WINDOW_HEIGHT);
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

    prepare_point_shadow_map_context();
    Self.point_shadow_map_shader.use();
    const point_light_projection = environment.point_shadow_map_projection();
    Self.point_shadow_map_shader.set_projection(&point_light_projection);
    for (0..NUM_LIGHTS) |light_index| {
        Self.point_shadow_map_shader.set_light_position(
            &environment.lights_position[light_index],
        );
        const face_views = environment.point_shadow_map_views(@intCast(light_index));
        for (&face_views, 0..) |*view, i| {
            const face =
                @as(u32, @intCast(gl.GL_TEXTURE_CUBE_MAP_POSITIVE_X)) + @as(u32, @intCast(i));
            gl.glFramebufferTexture2D(
                gl.GL_FRAMEBUFFER,
                gl.GL_DEPTH_ATTACHMENT,
                face,
                Self.point_shadow_maps.depth_cubes[light_index],
                0,
            );
            gl.glClearDepth(1.0);
            gl.glClear(gl.GL_DEPTH_BUFFER_BIT);
            Self.point_shadow_map_shader.set_face_view(view);
            for (Self.mesh_infos.slice()) |*mi| {
                Self.point_shadow_map_shader.set_mesh_params(&mi.model);
                mi.mesh.draw();
            }
        }
    }

    // _ = camera;
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
        &Self.point_shadow_maps,
    );
    for (Self.mesh_infos.slice()) |*mi| {
        Self.mesh_shader.set_mesh_params(&mi.model, &mi.material);
        mi.mesh.draw();
    }

    Self.cursor_shader.draw(environment.cursor_size);
}

const std = @import("std");
const builtin = @import("builtin");
const gl = @import("bindings/gl.zig");
const log = @import("log.zig");
const math = @import("math.zig");
const Mesh = @import("mesh.zig");

const Renderer = @import("renderer.zig");
const Platform = @import("platform.zig");
const FileMem = Platform.FileMem;

pub const Shader = struct {
    vertex_shader: u32,
    fragment_shader: u32,
    shader: u32,

    const Self = @This();

    pub fn init(vertex_shader_path: []const u8, fragment_shader_path: []const u8) Self {
        const vertex_shader_src =
            FileMem.init(vertex_shader_path) catch @panic("cannot read vertex shader");
        defer vertex_shader_src.deinit();

        const fragment_shader_src =
            FileMem.init(fragment_shader_path) catch @panic("cannot read fragment shader");
        defer fragment_shader_src.deinit();

        const vertex_shader = gl.glCreateShader(gl.GL_VERTEX_SHADER);
        const v_ptr = [_]*const u8{@ptrCast(vertex_shader_src.mem.ptr)};
        const v_len: i32 = @intCast(vertex_shader_src.mem.len);
        gl.glShaderSource(
            vertex_shader,
            1,
            @ptrCast(&v_ptr),
            @ptrCast(&v_len),
        );
        gl.glCompileShader(vertex_shader);
        check_shader_result(@src(), vertex_shader_path, vertex_shader, gl.GL_COMPILE_STATUS);

        const fragment_shader = gl.glCreateShader(gl.GL_FRAGMENT_SHADER);
        const f_ptr = [_]*const u8{@ptrCast(fragment_shader_src.mem.ptr)};
        const f_len: i32 = @intCast(fragment_shader_src.mem.len);
        gl.glShaderSource(
            fragment_shader,
            1,
            @ptrCast(&f_ptr),
            @ptrCast(&f_len),
        );
        gl.glCompileShader(fragment_shader);
        check_shader_result(@src(), fragment_shader_path, fragment_shader, gl.GL_COMPILE_STATUS);

        const shader = gl.glCreateProgram();
        gl.glAttachShader(shader, vertex_shader);
        gl.glAttachShader(shader, fragment_shader);
        gl.glLinkProgram(shader);
        check_program_result(@src(), shader, gl.GL_LINK_STATUS);

        return .{
            .vertex_shader = vertex_shader,
            .fragment_shader = fragment_shader,
            .shader = shader,
        };
    }

    pub fn get_uniform_location(self: *const Shader, name: [*c]const u8) i32 {
        return gl.glGetUniformLocation(self.shader, name);
    }

    pub fn use(self: *const Shader) void {
        gl.glUseProgram(self.shader);
    }

    fn check_shader_result(
        comptime src: std.builtin.SourceLocation,
        shader_path: []const u8,
        shader: u32,
        tag: u32,
    ) void {
        var success: i32 = undefined;
        gl.glGetShaderiv(shader, tag, &success);
        if (success != gl.GL_TRUE) {
            var buff: [1024]u8 = undefined;
            var s: i32 = undefined;
            gl.glGetShaderInfoLog(shader, 1024, &s, &buff);
            log.assert(
                src,
                false,
                "error in shader {s}: {s}({d})",
                .{ shader_path, buff[0..@intCast(s)], s },
            );
        }
    }

    fn check_program_result(
        comptime src: std.builtin.SourceLocation,
        shader: u32,
        tag: u32,
    ) void {
        var success: i32 = undefined;
        gl.glGetProgramiv(shader, tag, &success);
        if (success != gl.GL_TRUE) {
            var buff: [1024]u8 = undefined;
            var s: i32 = undefined;
            gl.glGetProgramInfoLog(shader, 1024, &s, &buff);
            log.assert(
                src,
                false,
                "error in shader: {s}({d})",
                .{ buff[0..@intCast(s)], s },
            );
        }
    }
};

pub const MeshShader = struct {
    shader: Shader,

    view_loc: i32,
    projection_loc: i32,
    model_loc: i32,

    camera_pos_loc: i32,
    lights_pos_loc: i32,
    lights_color_loc: i32,
    direct_light_direction: i32,
    direct_light_color: i32,
    albedo_loc: i32,
    metallic_loc: i32,
    roughness_loc: i32,
    ao_loc: i32,

    const Self = @This();

    pub fn init() Self {
        const shader = Shader.init("resources/shaders/mesh.vert", "resources/shaders/mesh.frag");

        const view_loc = shader.get_uniform_location("view");
        const projection_loc = shader.get_uniform_location("projection");
        const model_loc = shader.get_uniform_location("model");

        const camera_pos_loc = shader.get_uniform_location("camera_position");
        const lights_pos_loc = shader.get_uniform_location("light_positions");
        const lights_color_loc = shader.get_uniform_location("light_colors");
        const direct_light_direction = shader.get_uniform_location("direct_light_direction");
        const direct_light_color = shader.get_uniform_location("direct_light_color");
        const albedo_loc = shader.get_uniform_location("albedo");
        const metallic_loc = shader.get_uniform_location("metallic");
        const roughness_loc = shader.get_uniform_location("roughness");
        const ao_loc = shader.get_uniform_location("ao");

        return .{
            .shader = shader,
            .view_loc = view_loc,
            .projection_loc = projection_loc,
            .model_loc = model_loc,
            .camera_pos_loc = camera_pos_loc,
            .lights_pos_loc = lights_pos_loc,
            .lights_color_loc = lights_color_loc,
            .direct_light_direction = direct_light_direction,
            .direct_light_color = direct_light_color,
            .albedo_loc = albedo_loc,
            .metallic_loc = metallic_loc,
            .roughness_loc = roughness_loc,
            .ao_loc = ao_loc,
        };
    }

    pub fn use(self: *const Self) void {
        self.shader.use();
    }

    pub fn set_scene_params(
        self: *const Self,
        camera_view: *const math.Mat4,
        camera_position: *const math.Vec3,
        camera_projection: *const math.Mat4,
        environment: *const Renderer.Environment,
    ) void {
        gl.glUniformMatrix4fv(self.view_loc, 1, gl.GL_FALSE, @ptrCast(camera_view));
        gl.glUniformMatrix4fv(self.projection_loc, 1, gl.GL_FALSE, @ptrCast(camera_projection));

        gl.glUniform3f(self.camera_pos_loc, camera_position.x, camera_position.y, camera_position.z);
        gl.glUniform3fv(
            self.lights_pos_loc,
            environment.lights_position.len,
            @ptrCast(&environment.lights_position),
        );
        gl.glUniform3fv(
            self.lights_color_loc,
            environment.lights_color.len,
            @ptrCast(&environment.lights_color),
        );
        gl.glUniform3f(
            self.direct_light_direction,
            environment.direct_light_direction.x,
            environment.direct_light_direction.y,
            environment.direct_light_direction.z,
        );
        gl.glUniform3f(
            self.direct_light_color,
            environment.direct_light_color.r,
            environment.direct_light_color.g,
            environment.direct_light_color.b,
        );
    }

    pub fn set_mesh_params(
        self: *const Self,
        model: *const math.Mat4,
        material: *const Mesh.Material,
    ) void {
        gl.glUniformMatrix4fv(self.model_loc, 1, gl.GL_FALSE, @ptrCast(model));
        gl.glUniform3f(self.albedo_loc, material.albedo.r, material.albedo.g, material.albedo.b);
        gl.glUniform1f(self.metallic_loc, material.metallic);
        gl.glUniform1f(self.roughness_loc, material.roughness);
        gl.glUniform1f(self.ao_loc, 0.03);
    }
};

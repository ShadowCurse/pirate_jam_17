const std = @import("std");
const builtin = @import("builtin");
const gl = @import("bindings/gl.zig");
const log = @import("log.zig");
const math = @import("math.zig");
const gpu = @import("gpu.zig");

const Mesh = @import("mesh.zig");
const Renderer = @import("renderer.zig");
const Platform = @import("platform.zig");
const FileMem = Platform.FileMem;

const Assets = @import("assets.zig");

const Ui = @import("ui.zig");

pub const Shader = struct {
    shader: u32,

    const WEBGL_DEFINE = "#define WEBGL 0";
    const Self = @This();

    pub fn init(
        vertex_shader_path: []const u8,
        fragment_shader_path: []const u8,
    ) Self {
        const vertex_shader_src =
            FileMem.init(vertex_shader_path) catch @panic("cannot read vertex shader");
        defer vertex_shader_src.deinit();

        if (builtin.os.tag == .emscripten) {
            if (std.mem.indexOf(u8, vertex_shader_src.mem, WEBGL_DEFINE)) |index|
                vertex_shader_src.mem[index + WEBGL_DEFINE.len] = '1';
        }

        const fragment_shader_src =
            FileMem.init(fragment_shader_path) catch @panic("cannot read fragment shader");
        defer fragment_shader_src.deinit();

        if (builtin.os.tag == .emscripten) {
            if (std.mem.indexOf(u8, fragment_shader_src.mem, WEBGL_DEFINE)) |index|
                fragment_shader_src.mem[index + WEBGL_DEFINE.len] = '1';
        }

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

        gl.glDeleteShader(vertex_shader);
        gl.glDeleteShader(fragment_shader);

        return .{
            .shader = shader,
        };
    }

    pub fn get_uniform_location(self: *const Shader, name: [*c]const u8) i32 {
        const v = gl.glGetUniformLocation(self.shader, name);
        if (v == -1)
            log.warn(
                @src(),
                "error getting the uniform location: {s}",
                .{name},
            );
        return v;
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

    view: i32,
    projection: i32,
    model: i32,
    shadow_map_view: i32,
    shadow_map_projection: i32,

    camera_pos: i32,
    lights_pos: i32,
    lights_color: i32,
    direct_light_direction: i32,
    direct_light_color: i32,
    albedo: i32,
    metallic: i32,
    roughness: i32,
    ao: i32,
    emissive: i32,
    use_textures: i32,
    albedo_texture: i32,
    metallic_texture: i32,
    roughness_texture: i32,
    normal_texture: i32,

    use_shadow_map: i32,
    direct_light_shadow: i32,
    point_light_0_shadow: i32,
    point_light_1_shadow: i32,
    point_light_2_shadow: i32,
    point_light_3_shadow: i32,

    const USE_ALBEDO_TEXTURE = 1 << 0;
    const USE_METALLIC_TEXTURE = 1 << 1;
    const USE_ROUNGHNESS_TEXTURE = 1 << 2;
    const USE_NORMAL_TEXTURE = 1 << 3;
    const Self = @This();

    pub fn init() Self {
        const shader = Shader.init(
            "resources/shaders/mesh.vert",
            "resources/shaders/mesh.frag",
        );

        return .{
            .shader = shader,
            .view = shader.get_uniform_location("view"),
            .projection = shader.get_uniform_location("projection"),
            .model = shader.get_uniform_location("model"),
            .shadow_map_view = shader.get_uniform_location("shadow_map_view"),
            .shadow_map_projection = shader.get_uniform_location("shadow_map_projection"),
            .camera_pos = shader.get_uniform_location("camera_pos"),
            .lights_pos = shader.get_uniform_location("lights_pos"),
            .lights_color = shader.get_uniform_location("lights_color"),
            .direct_light_direction = shader.get_uniform_location("direct_light_direction"),
            .direct_light_color = shader.get_uniform_location("direct_light_color"),
            .albedo = shader.get_uniform_location("flat_albedo"),
            .metallic = shader.get_uniform_location("flat_metallic"),
            .roughness = shader.get_uniform_location("flat_roughness"),
            .ao = shader.get_uniform_location("ao"),
            .emissive = shader.get_uniform_location("emissive"),
            .use_textures = shader.get_uniform_location("use_textures"),
            .albedo_texture = shader.get_uniform_location("albedo_texture"),
            .metallic_texture = shader.get_uniform_location("metallic_texture"),
            .roughness_texture = shader.get_uniform_location("roughness_texture"),
            .normal_texture = shader.get_uniform_location("normal_texture"),
            .use_shadow_map = shader.get_uniform_location("use_shadow_map"),
            .direct_light_shadow = shader.get_uniform_location("direct_light_shadow"),
            .point_light_0_shadow = shader.get_uniform_location("point_light_0_shadow"),
            .point_light_1_shadow = shader.get_uniform_location("point_light_1_shadow"),
            .point_light_2_shadow = shader.get_uniform_location("point_light_2_shadow"),
            .point_light_3_shadow = shader.get_uniform_location("point_light_3_shadow"),
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
        direct_light_shadow: *const gpu.ShadowMap,
        point_light_shadows: *const gpu.PointShadowMaps,
        use_shadow_map: bool,
    ) void {
        gl.glUniformMatrix4fv(self.view, 1, gl.GL_FALSE, @ptrCast(camera_view));
        gl.glUniformMatrix4fv(self.projection, 1, gl.GL_FALSE, @ptrCast(camera_projection));

        const shadow_map_view = environment.shadow_map_view();
        const shadow_map_projection = environment.shadow_map_projection();
        gl.glUniformMatrix4fv(
            self.shadow_map_view,
            1,
            gl.GL_FALSE,
            @ptrCast(&shadow_map_view),
        );
        gl.glUniformMatrix4fv(
            self.shadow_map_projection,
            1,
            gl.GL_FALSE,
            @ptrCast(&shadow_map_projection),
        );

        gl.glUniform3f(self.camera_pos, camera_position.x, camera_position.y, camera_position.z);
        gl.glUniform3fv(
            self.lights_pos,
            environment.lights_position.len,
            @ptrCast(&environment.lights_position),
        );
        gl.glUniform3fv(
            self.lights_color,
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

        if (use_shadow_map) {
            gl.glActiveTexture(gl.GL_TEXTURE0);
            gl.glBindTexture(gl.GL_TEXTURE_2D, direct_light_shadow.depth_texture);
            for (point_light_shadows.depth_cubes, 0..) |dc, i| {
                gl.glActiveTexture(@as(u32, @intCast(gl.GL_TEXTURE1 + @as(i32, @intCast(i)))));
                gl.glBindTexture(gl.GL_TEXTURE_CUBE_MAP, dc);
            }
            gl.glUniform1i(self.direct_light_shadow, 0);
            gl.glUniform1i(self.point_light_0_shadow, 1);
            gl.glUniform1i(self.point_light_1_shadow, 2);
            gl.glUniform1i(self.point_light_2_shadow, 3);
            gl.glUniform1i(self.point_light_3_shadow, 4);
            gl.glUniform1i(self.use_shadow_map, 1);
        } else gl.glUniform1i(self.use_shadow_map, 0);
    }

    pub fn set_mesh_params(
        self: *const Self,
        model: *const math.Mat4,
        material: *const Mesh.Material,
    ) void {
        gl.glUniformMatrix4fv(self.model, 1, gl.GL_FALSE, @ptrCast(model));
        gl.glUniform3f(self.albedo, material.albedo.r, material.albedo.g, material.albedo.b);
        gl.glUniform1f(self.metallic, material.metallic);
        gl.glUniform1f(self.roughness, material.roughness);
        gl.glUniform1f(self.ao, 0.03);
        gl.glUniform1f(self.emissive, material.emissive_strength);

        var use_textures: i32 = 0;
        if (material.albedo_texture) |at| {
            use_textures |= USE_ALBEDO_TEXTURE;
            const t = Assets.gpu_textures.getPtrConst(at);
            gl.glActiveTexture(gl.GL_TEXTURE5);
            gl.glBindTexture(gl.GL_TEXTURE_2D, t.texture);
            gl.glUniform1i(self.albedo_texture, 5);
        }
        if (material.metallic_texture) |at| {
            use_textures |= USE_METALLIC_TEXTURE;
            const t = Assets.gpu_textures.getPtrConst(at);
            gl.glActiveTexture(gl.GL_TEXTURE6);
            gl.glBindTexture(gl.GL_TEXTURE_2D, t.texture);
            gl.glUniform1i(self.metallic_texture, 6);
        }
        if (material.roughness_texture) |at| {
            use_textures |= USE_ROUNGHNESS_TEXTURE;
            const t = Assets.gpu_textures.getPtrConst(at);
            gl.glActiveTexture(gl.GL_TEXTURE7);
            gl.glBindTexture(gl.GL_TEXTURE_2D, t.texture);
            gl.glUniform1i(self.roughness_texture, 7);
        }
        if (material.normal_texture) |at| {
            use_textures |= USE_NORMAL_TEXTURE;
            const t = Assets.gpu_textures.getPtrConst(at);
            gl.glActiveTexture(gl.GL_TEXTURE8);
            gl.glBindTexture(gl.GL_TEXTURE_2D, t.texture);
            gl.glUniform1i(self.normal_texture, 8);
        }

        gl.glUniform1i(self.use_textures, use_textures);
    }
};

pub const ShadowMapShader = struct {
    shader: Shader,

    view_loc: i32,
    projection_loc: i32,
    model_loc: i32,

    const Self = @This();

    pub fn init() Self {
        const shader = Shader.init(
            "resources/shaders/shadow_map.vert",
            "resources/shaders/shadow_map.frag",
        );

        const view_loc = shader.get_uniform_location("view");
        const projection_loc = shader.get_uniform_location("projection");
        const model_loc = shader.get_uniform_location("model");

        return .{
            .shader = shader,
            .view_loc = view_loc,
            .projection_loc = projection_loc,
            .model_loc = model_loc,
        };
    }

    pub fn use(self: *const Self) void {
        self.shader.use();
    }

    pub fn set_params(
        self: *const Self,
        environment: *const Renderer.Environment,
    ) void {
        const view = environment.shadow_map_view();
        const projection = environment.shadow_map_projection();

        gl.glUniformMatrix4fv(self.view_loc, 1, gl.GL_FALSE, @ptrCast(&view));
        gl.glUniformMatrix4fv(self.projection_loc, 1, gl.GL_FALSE, @ptrCast(&projection));
    }

    pub fn set_mesh_params(
        self: *const Self,
        model: *const math.Mat4,
    ) void {
        gl.glUniformMatrix4fv(self.model_loc, 1, gl.GL_FALSE, @ptrCast(model));
    }
};

pub const PointShadowMapShader = struct {
    shader: Shader,

    view_loc: i32,
    projection_loc: i32,
    model_loc: i32,

    light_position_loc: i32,
    far_plane_loc: i32,

    const Self = @This();

    pub fn init() Self {
        const shader = Shader.init(
            "resources/shaders/shadow_map.vert",
            "resources/shaders/point_shadow_map.frag",
        );

        const view_loc = shader.get_uniform_location("view");
        const projection_loc = shader.get_uniform_location("projection");
        const model_loc = shader.get_uniform_location("model");
        const light_position_loc = shader.get_uniform_location("light_position");
        const far_plane_loc = shader.get_uniform_location("far_plane");

        return .{
            .shader = shader,
            .view_loc = view_loc,
            .projection_loc = projection_loc,
            .model_loc = model_loc,
            .light_position_loc = light_position_loc,
            .far_plane_loc = far_plane_loc,
        };
    }

    pub fn use(self: *const Self) void {
        self.shader.use();
    }

    pub fn set_projection(
        self: *const Self,
        projection: *const math.Mat4,
    ) void {
        gl.glUniform1f(self.far_plane_loc, 10000.0);
        gl.glUniformMatrix4fv(self.projection_loc, 1, gl.GL_FALSE, @ptrCast(projection));
    }

    pub fn set_light_position(
        self: *const Self,
        light_position: *const math.Vec3,
    ) void {
        gl.glUniform3f(
            self.light_position_loc,
            light_position.x,
            light_position.y,
            light_position.z,
        );
    }

    pub fn set_face_view(
        self: *const Self,
        view: *const math.Mat4,
    ) void {
        gl.glUniformMatrix4fv(self.view_loc, 1, gl.GL_FALSE, @ptrCast(view));
    }

    pub fn set_mesh_params(
        self: *const Self,
        model: *const math.Mat4,
    ) void {
        gl.glUniformMatrix4fv(self.model_loc, 1, gl.GL_FALSE, @ptrCast(model));
    }
};

pub const UiShapeShader = struct {
    shader: Shader,

    size: i32,
    position: i32,
    window_size: i32,
    transparancy: i32,

    radius: i32,
    width: i32,

    const Self = @This();

    pub fn init() Self {
        const shader = Shader.init(
            "resources/shaders/ui_rect.vert",
            "resources/shaders/ui_shape.frag",
        );

        return .{
            .shader = shader,
            .size = shader.get_uniform_location("size"),
            .position = shader.get_uniform_location("position"),
            .window_size = shader.get_uniform_location("window_size"),
            .transparancy = shader.get_uniform_location("transparancy"),

            .radius = shader.get_uniform_location("radius"),
            .width = shader.get_uniform_location("width"),
        };
    }

    pub fn draw(
        self: *const Self,
        size: f32,
        position: math.Vec2,
        transparency: f32,
        radius: f32,
        width: f32,
    ) void {
        self.shader.use();
        gl.glUniform1f(self.size, size);
        gl.glUniform1f(self.radius, radius);
        gl.glUniform1f(self.width, width);
        gl.glUniform2f(self.position, position.x, position.y);
        gl.glUniform2f(self.window_size, Platform.WINDOW_WIDTH, Platform.WINDOW_HEIGHT);
        gl.glUniform1f(self.transparancy, transparency);

        gl.glDisable(gl.GL_DEPTH_TEST);
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 6);
        gl.glEnable(gl.GL_DEPTH_TEST);
    }
};

pub const UiTextureShader = struct {
    shader: Shader,

    size: i32,
    position: i32,
    window_size: i32,
    transparancy: i32,

    const Self = @This();

    pub fn init() Self {
        const shader = Shader.init(
            "resources/shaders/ui_rect.vert",
            "resources/shaders/ui_texture.frag",
        );

        return .{
            .shader = shader,
            .size = shader.get_uniform_location("size"),
            .position = shader.get_uniform_location("position"),
            .window_size = shader.get_uniform_location("window_size"),
            .transparancy = shader.get_uniform_location("transparancy"),
        };
    }

    pub fn draw(
        self: *const Self,
        size: f32,
        position: math.Vec2,
        transparency: f32,
        texture: *const gpu.Texture,
    ) void {
        self.shader.use();
        gl.glUniform1f(self.size, size);
        gl.glUniform2f(self.position, position.x, position.y);
        gl.glUniform2f(self.window_size, Platform.WINDOW_WIDTH, Platform.WINDOW_HEIGHT);
        gl.glUniform1f(self.transparancy, transparency);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, texture.texture);

        gl.glDisable(gl.GL_DEPTH_TEST);
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 6);
        gl.glEnable(gl.GL_DEPTH_TEST);
    }
};

pub const PostProcessingShader = struct {
    shader: Shader,

    window_size: i32,
    blur_strength: i32,

    const Self = @This();

    pub fn init() Self {
        const shader = Shader.init(
            "resources/shaders/post_processing.vert",
            "resources/shaders/post_processing.frag",
        );

        return .{
            .shader = shader,
            .window_size = shader.get_uniform_location("window_size"),
            .blur_strength = shader.get_uniform_location("blur_strength"),
        };
    }

    pub fn draw(
        self: *const Self,
        blur_strength: f32,
        texture: u32,
    ) void {
        self.shader.use();
        gl.glUniform2f(self.window_size, Platform.WINDOW_WIDTH, Platform.WINDOW_HEIGHT);
        gl.glUniform1f(self.blur_strength, blur_strength);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, texture);
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 6);
    }
};

pub const SkyboxShader = struct {
    shader: Shader,

    view: i32,
    projection: i32,

    const Self = @This();

    pub fn init() Self {
        const shader = Shader.init(
            "resources/shaders/skybox.vert",
            "resources/shaders/skybox.frag",
        );

        return .{
            .shader = shader,
            .view = shader.get_uniform_location("view"),
            .projection = shader.get_uniform_location("projection"),
        };
    }

    pub fn draw(
        self: *const Self,
        texture: u32,
        view: *const math.Mat4,
        projection: *const math.Mat4,
    ) void {
        self.shader.use();
        gl.glUniformMatrix4fv(self.view, 1, gl.GL_FALSE, @ptrCast(view));
        gl.glUniformMatrix4fv(self.projection, 1, gl.GL_FALSE, @ptrCast(projection));
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_CUBE_MAP, texture);
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 36);
    }
};

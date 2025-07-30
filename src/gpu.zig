const std = @import("std");
const builtin = @import("builtin");
const log = @import("log.zig");
const gl = @import("bindings/gl.zig");
const math = @import("math.zig");

const Platform = @import("platform.zig");
const Renderer = @import("renderer.zig");

pub const Framebuffer = struct {
    framebuffer: u32,
    texture: u32,
    depth_texture: u32,

    pub const WIDTH = Platform.WINDOW_WIDTH;
    pub const HEIGHT = Platform.WINDOW_HEIGHT;

    pub fn init() Framebuffer {
        var framebuffer: u32 = undefined;
        gl.glGenFramebuffers(1, &framebuffer);
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, framebuffer);

        var texture: u32 = undefined;
        gl.glGenTextures(1, &texture);
        gl.glBindTexture(gl.GL_TEXTURE_2D, texture);
        gl.glTexImage2D(
            gl.GL_TEXTURE_2D,
            0,
            gl.GL_RGBA,
            WIDTH,
            HEIGHT,
            0,
            gl.GL_RGBA,
            gl.GL_UNSIGNED_BYTE,
            null,
        );
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
        gl.glFramebufferTexture2D(
            gl.GL_FRAMEBUFFER,
            gl.GL_COLOR_ATTACHMENT0,
            gl.GL_TEXTURE_2D,
            texture,
            0,
        );

        var depth_texture: u32 = undefined;
        gl.glGenRenderbuffers(1, &depth_texture);
        gl.glBindRenderbuffer(gl.GL_RENDERBUFFER, depth_texture);
        gl.glRenderbufferStorage(gl.GL_RENDERBUFFER, gl.GL_DEPTH_COMPONENT32F, WIDTH, HEIGHT);
        gl.glFramebufferRenderbuffer(
            gl.GL_FRAMEBUFFER,
            gl.GL_DEPTH_ATTACHMENT,
            gl.GL_RENDERBUFFER,
            depth_texture,
        );

        if (gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE)
            log.err(@src(), "Framebuffer is not complete", .{});

        return .{
            .framebuffer = framebuffer,
            .texture = texture,
            .depth_texture = depth_texture,
        };
    }
};

pub const Mesh = struct {
    vertex_buffer: u32,
    index_buffer: u32,
    instance_buffer: u32,
    n_indices: i32,
    vertex_array: u32,

    instance_infos: std.BoundedArray(InstanceInfo, MAX_INSTANCES) = .{},

    pub const MAX_INSTANCES = 32;
    pub const InstanceInfo = extern struct {
        model: math.Mat4,
        albedo: math.Color3,
        metallic: f32,
        roughness: f32,
        emissive_strength: f32,
        uv_scale: f32,
        options: i32,
    };

    const Self = @This();

    pub fn init(VERTEX_TYPE: type, vertices: []const VERTEX_TYPE, indices: []const u32) Self {
        var vertex_buffer: u32 = undefined;
        gl.glGenBuffers(1, &vertex_buffer);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vertex_buffer);
        gl.glBufferData(
            gl.GL_ARRAY_BUFFER,
            @intCast(@sizeOf(VERTEX_TYPE) * vertices.len),
            vertices.ptr,
            gl.GL_STATIC_DRAW,
        );

        var index_buffer: u32 = undefined;
        gl.glGenBuffers(1, &index_buffer);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, index_buffer);
        gl.glBufferData(
            gl.GL_ELEMENT_ARRAY_BUFFER,
            @intCast(@sizeOf(u32) * indices.len),
            indices.ptr,
            gl.GL_STATIC_DRAW,
        );
        const n_indices: i32 = @intCast(indices.len);

        var instance_buffer: u32 = undefined;
        gl.glGenBuffers(1, &instance_buffer);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, instance_buffer);
        gl.glBufferData(
            gl.GL_ARRAY_BUFFER,
            @intCast(@sizeOf(InstanceInfo) * 32),
            null,
            gl.GL_DYNAMIC_DRAW,
        );

        var vertex_array: u32 = undefined;
        gl.glGenVertexArrays(1, &vertex_array);
        gl.glBindVertexArray(vertex_array);

        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vertex_buffer);
        VERTEX_TYPE.set_attributes();

        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, instance_buffer);
        // model
        gl.glVertexAttribPointer(6, 4, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(InstanceInfo), @ptrFromInt(0 * @sizeOf(f32)));
        gl.glVertexAttribPointer(7, 4, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(InstanceInfo), @ptrFromInt(4 * @sizeOf(f32)));
        gl.glVertexAttribPointer(8, 4, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(InstanceInfo), @ptrFromInt(8 * @sizeOf(f32)));
        gl.glVertexAttribPointer(9, 4, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(InstanceInfo), @ptrFromInt(12 * @sizeOf(f32)));
        // albedo + metallic
        gl.glVertexAttribPointer(10, 4, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(InstanceInfo), @ptrFromInt(16 * @sizeOf(f32)));
        // else
        gl.glVertexAttribPointer(11, 4, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(InstanceInfo), @ptrFromInt(20 * @sizeOf(f32)));
        gl.glEnableVertexAttribArray(6);
        gl.glEnableVertexAttribArray(7);
        gl.glEnableVertexAttribArray(8);
        gl.glEnableVertexAttribArray(9);
        gl.glEnableVertexAttribArray(10);
        gl.glEnableVertexAttribArray(11);

        gl.glVertexAttribDivisor(6, 1);
        gl.glVertexAttribDivisor(7, 1);
        gl.glVertexAttribDivisor(8, 1);
        gl.glVertexAttribDivisor(9, 1);
        gl.glVertexAttribDivisor(10, 1);
        gl.glVertexAttribDivisor(11, 1);

        return .{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .instance_buffer = instance_buffer,
            .n_indices = n_indices,
            .vertex_array = vertex_array,
        };
    }

    const M = @import("mesh.zig");
    pub fn from_mesh(mesh: *const M) Self {
        return Self.init(M.Vertex, mesh.vertices, mesh.indices);
    }

    pub fn add_instance_info(self: *Self, info: InstanceInfo) void {
        self.instance_infos.append(info) catch |e| {
            log.err(@src(), "Cannot add more instance infos: {any}", .{e});
        };
    }

    pub fn draw_instanced(self: *const Self) void {
        const infos = self.instance_infos.slice();
        if (infos.len == 0) return;

        // there is a glNamedBufferSubData, but web does not support it.
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.instance_buffer);
        gl.glBufferSubData(
            gl.GL_ARRAY_BUFFER,
            0,
            @intCast(@sizeOf(InstanceInfo) * infos.len),
            infos.ptr,
        );

        gl.glBindVertexArray(self.vertex_array);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.index_buffer);
        gl.glDrawElementsInstanced(
            gl.GL_TRIANGLES,
            self.n_indices,
            gl.GL_UNSIGNED_INT,
            null,
            @intCast(infos.len),
        );
    }

    pub fn clear_instance_infos(self: *Self) void {
        self.instance_infos.clear();
    }
};

pub const Texture = struct {
    texture: u32,

    const Self = @This();

    pub fn init(data: [*]u8, width: u32, height: u32) Self {
        var texture: u32 = undefined;
        gl.glGenTextures(1, &texture);
        gl.glBindTexture(gl.GL_TEXTURE_2D, texture);

        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_REPEAT);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_REPEAT);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR_MIPMAP_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);

        gl.glTexImage2D(
            gl.GL_TEXTURE_2D,
            0,
            gl.GL_RGBA,
            @intCast(width),
            @intCast(height),
            0,
            gl.GL_RGBA,
            gl.GL_UNSIGNED_BYTE,
            @ptrCast(data),
        );
        gl.glGenerateMipmap(gl.GL_TEXTURE_2D);

        return .{
            .texture = texture,
        };
    }
};

pub const ShadowMap = struct {
    framebuffer: u32,
    depth_texture: u32,

    pub const SHADOW_WIDTH = 1920;
    pub const SHADOW_HEIGHT = 1920;
    const Self = ShadowMap;

    pub fn init() ShadowMap {
        var framebuffer: u32 = undefined;
        gl.glGenFramebuffers(1, &framebuffer);

        var depth_texture: u32 = undefined;
        gl.glGenTextures(1, &depth_texture);
        gl.glBindTexture(gl.GL_TEXTURE_2D, depth_texture);
        gl.glTexImage2D(
            gl.GL_TEXTURE_2D,
            0,
            gl.GL_DEPTH_COMPONENT32F,
            SHADOW_WIDTH,
            SHADOW_HEIGHT,
            0,
            gl.GL_DEPTH_COMPONENT,
            gl.GL_FLOAT,
            null,
        );
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);

        if (builtin.os.tag == .emscripten) {
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
        } else {
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_BORDER);
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_BORDER);
            const border_color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 };
            gl.glTexParameterfv(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_BORDER_COLOR, &border_color);
        }

        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, framebuffer);
        gl.glFramebufferTexture2D(
            gl.GL_FRAMEBUFFER,
            gl.GL_DEPTH_ATTACHMENT,
            gl.GL_TEXTURE_2D,
            depth_texture,
            0,
        );
        gl.glDrawBuffers(gl.GL_NONE, null);
        gl.glReadBuffer(gl.GL_NONE);

        return .{
            .framebuffer = framebuffer,
            .depth_texture = depth_texture,
        };
    }
};

pub const PointShadowMaps = struct {
    framebuffer: u32,
    depth_cubes: [Renderer.MAX_LIGHTS]u32,

    pub const SHADOW_WIDTH = Platform.WINDOW_WIDTH;
    pub const SHADOW_HEIGHT = Platform.WINDOW_WIDTH; //WINDOW_HEIGHT;
    const Self = ShadowMap;

    pub fn init() PointShadowMaps {
        var framebuffer: u32 = undefined;
        gl.glGenFramebuffers(1, &framebuffer);

        var depth_cubes: [Renderer.MAX_LIGHTS]u32 = undefined;
        for (&depth_cubes) |*dc| {
            gl.glGenTextures(1, dc);
            gl.glBindTexture(gl.GL_TEXTURE_CUBE_MAP, dc.*);
            for (0..6) |i| {
                const index =
                    @as(u32, @intCast(gl.GL_TEXTURE_CUBE_MAP_POSITIVE_X)) + @as(u32, @intCast(i));
                gl.glTexImage2D(
                    index,
                    0,
                    gl.GL_DEPTH_COMPONENT32F,
                    SHADOW_WIDTH,
                    SHADOW_HEIGHT,
                    0,
                    gl.GL_DEPTH_COMPONENT,
                    gl.GL_FLOAT,
                    null,
                );
            }
            gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
            gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);

            gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
            gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
            gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_WRAP_R, gl.GL_CLAMP_TO_EDGE);
        }

        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, framebuffer);
        gl.glDrawBuffers(gl.GL_NONE, null);
        gl.glReadBuffer(gl.GL_NONE);

        return .{
            .framebuffer = framebuffer,
            .depth_cubes = depth_cubes,
        };
    }
};

pub const Skybox = struct {
    texture: u32,

    const Self = @This();

    pub fn init(faces: *const [6][*]u8, width: u32, height: u32) Self {
        var texture: u32 = undefined;
        gl.glGenTextures(1, &texture);
        gl.glBindTexture(gl.GL_TEXTURE_CUBE_MAP, texture);
        for (faces, 0..) |face, i| {
            const index =
                @as(u32, @intCast(gl.GL_TEXTURE_CUBE_MAP_POSITIVE_X)) + @as(u32, @intCast(i));
            gl.glTexImage2D(
                index,
                0,
                gl.GL_RGB,
                @intCast(width),
                @intCast(height),
                0,
                gl.GL_RGB,
                gl.GL_UNSIGNED_BYTE,
                face,
            );
        }
        gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);

        gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_WRAP_R, gl.GL_CLAMP_TO_EDGE);

        return .{
            .texture = texture,
        };
    }
};
